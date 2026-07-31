pub mod feature_cache;

use feature_cache::FeatureIndexCache;

use crate::protocol::{
    error::HidppError,
    feature::{FeatureCode, FeatureIndex},
    message::{
        HidppMessage, LongMessage, ShortMessage, DEVICE_ID_WIRED, ERROR_FEATURE_INDEX, SOFTWARE_ID,
    },
};
use crate::transport::HidTransport;

const READ_TIMEOUT_MS: i32 = 2000;

/// Central handle for communicating with a HID++ 2.0 device.
/// Generic over `T: HidTransport` so tests can inject `MockTransport`.
pub struct HidppDevice<T: HidTransport> {
    transport: T,
    device_id: u8,
    feature_cache: FeatureIndexCache,
}

impl<T: HidTransport> HidppDevice<T> {
    pub fn new(transport: T) -> Self {
        Self::with_device_id(transport, DEVICE_ID_WIRED)
    }

    pub fn with_device_id(transport: T, device_id: u8) -> Self {
        Self {
            transport,
            device_id,
            feature_cache: FeatureIndexCache::new(),
        }
    }

    /// Change the HID++ device address and discard indices cached for the previous
    /// address. Dedicated LIGHTSPEED receivers may expose the mouse at 0xFF while
    /// Unifying receivers expose paired devices at 0x01..0x06.
    pub fn set_device_id(&mut self, device_id: u8) {
        self.device_id = device_id;
        self.feature_cache = FeatureIndexCache::new();
    }

    /// Read the next valid HID++ message for this device address.
    ///
    /// This is used by event-oriented features such as MouseButtonSpy. Responses
    /// for other receiver slots are discarded.
    pub fn read_message(&self, timeout_ms: i32) -> Result<HidppMessage, HidppError> {
        let mut buf = [0u8; 20];
        loop {
            let n = self.transport.read(&mut buf, timeout_ms)?;
            if n < 7 {
                continue;
            }
            let message = match HidppMessage::from_bytes(&buf[..n]) {
                Ok(message) => message,
                Err(_) => continue,
            };
            if message.device_id() == self.device_id {
                return Ok(message);
            }
        }
    }

    /// Test-only access to the underlying transport, for inspecting the bytes
    /// written by a feature call (e.g. with `MockTransport::written_data`).
    #[cfg(test)]
    pub(crate) fn transport(&self) -> &T {
        &self.transport
    }

    /// Resolve the runtime index for a feature code.
    /// Result is cached; subsequent calls for the same code are instant.
    pub fn get_feature_index(&self, code: FeatureCode) -> Result<FeatureIndex, HidppError> {
        // IRoot is always at index 0 — no need to query
        if code == FeatureCode::IRoot {
            return Ok(FeatureIndex::IROOT);
        }

        if let Some(cached) = self.feature_cache.get(code) {
            return Ok(cached);
        }

        // Query IRoot (feature index 0, function 0 = GetFeature)
        let code_u16 = code.as_u16();
        let hi = (code_u16 >> 8) as u8;
        let lo = (code_u16 & 0xFF) as u8;

        let response = self.call_raw_short(
            FeatureIndex::IROOT.0,
            0, // function 0 = GetFeature
            [hi, lo, 0x00, 0x00],
        )?;

        let index = FeatureIndex(response.params()[0]);

        if index.is_absent() {
            return Err(HidppError::FeatureNotSupported {
                feature_code: code_u16,
            });
        }

        self.feature_cache.insert(code, index);
        Ok(index)
    }

    /// Low-level call using a SHORT message, returns parsed response.
    pub fn call_feature_short(
        &self,
        code: FeatureCode,
        function: u8,
        params: [u8; 4],
    ) -> Result<HidppMessage, HidppError> {
        let index = self.get_feature_index(code)?;
        self.call_raw_short(index.0, function, params)
    }

    /// Low-level call using a LONG message, returns parsed response.
    pub fn call_feature_long(
        &self,
        code: FeatureCode,
        function: u8,
        params: [u8; 16],
    ) -> Result<HidppMessage, HidppError> {
        let index = self.get_feature_index(code)?;
        self.call_raw_long(index.0, function, params)
    }

    fn call_raw_short(
        &self,
        feature_index: u8,
        function: u8,
        params: [u8; 4],
    ) -> Result<HidppMessage, HidppError> {
        let msg = ShortMessage::new(self.device_id, feature_index, function, params);
        let write_buf = msg.to_write_buf();
        self.transport.write(&write_buf)?;
        self.read_response(feature_index, function)
    }

    fn call_raw_long(
        &self,
        feature_index: u8,
        function: u8,
        params: [u8; 16],
    ) -> Result<HidppMessage, HidppError> {
        let msg = LongMessage::new(self.device_id, feature_index, function, params);
        let write_buf = msg.to_write_buf();
        self.transport.write(&write_buf)?;
        self.read_response(feature_index, function)
    }

    /// Read a response, skipping unrelated HID reports until we get one
    /// matching our feature_index + function, or a HID++ error response.
    fn read_response(&self, feature_index: u8, function: u8) -> Result<HidppMessage, HidppError> {
        let mut buf = [0u8; 20];
        let expected_function_id = (function << 4) | SOFTWARE_ID;

        // Shared receivers can be noisy (other HID++ clients and button events).
        // Responses arrive immediately after a write, so allow a generous number
        // of fast skips while the per-read timeout still bounds a quiet channel.
        for _ in 0..128 {
            let n = self.transport.read(&mut buf, READ_TIMEOUT_MS)?;
            if n < 7 {
                continue;
            }

            let msg = match HidppMessage::from_bytes(&buf[..n]) {
                Ok(m) => m,
                Err(_) => continue,
            };

            // Shared LIGHTSPEED receivers multiplex several paired devices and may
            // continuously emit unrelated HID++ events. Never let a response from
            // another receiver slot satisfy this request.
            if msg.device_id() != self.device_id {
                continue;
            }

            // HID++ error response: feature_index=0xFF
            if msg.feature_index() == ERROR_FEATURE_INDEX {
                let params = msg.params();
                // Error wire format is [report, device, 0xFF,
                // original feature index, original function/SWID, error code].
                // Ignore errors that belong to another shared client.
                if msg.function_id() == feature_index
                    && params.first().copied() == Some(expected_function_id)
                {
                    return Err(HidppError::DeviceError {
                        feature_index,
                        error_code: params.get(1).copied().unwrap_or(0),
                    });
                }
                continue;
            }

            // The low nibble is essential: ID 0 is used by notifications, while
            // other macOS clients may query the same feature and function.
            if msg.feature_index() == feature_index && msg.function_id() == expected_function_id {
                return Ok(msg);
            }
            // Otherwise it's an unrelated report; skip and retry
        }

        Err(HidppError::Timeout {
            timeout_ms: READ_TIMEOUT_MS,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::MockTransport;

    /// Build a SHORT response with given feature_index, function, and params
    fn make_short_response(feature_index: u8, function: u8, params: [u8; 4]) -> Vec<u8> {
        vec![
            0x10, // SHORT_REPORT_ID
            0xFF, // device_id
            feature_index,
            (function << 4) | SOFTWARE_ID,
            params[0],
            params[1],
            params[2],
        ]
    }

    #[test]
    fn get_feature_index_caches_result() {
        let transport = MockTransport::new();
        // IRoot response: feature index 0x00, fn 0, response says DPI is at index 0x03
        transport.push_response(make_short_response(0x00, 0x00, [0x03, 0x00, 0x00, 0x00]));

        let device = HidppDevice::new(transport);
        let idx = device
            .get_feature_index(FeatureCode::AdjustableDpi)
            .unwrap();
        assert_eq!(idx.0, 0x03);

        // Second call should hit cache — no additional response needed
        let idx2 = device
            .get_feature_index(FeatureCode::AdjustableDpi)
            .unwrap();
        assert_eq!(idx2.0, 0x03);
    }

    #[test]
    fn ignores_response_from_another_receiver_slot() {
        let transport = MockTransport::new();
        // Slot 1 reports "absent" first, but this request belongs to slot 2.
        transport.push_response(vec![0x10, 0x01, 0x00, SOFTWARE_ID, 0x00, 0, 0]);
        transport.push_response(vec![0x10, 0x02, 0x00, SOFTWARE_ID, 0x14, 0, 0]);

        let device = HidppDevice::with_device_id(transport, 0x02);
        let idx = device
            .get_feature_index(FeatureCode::OnboardProfiles)
            .unwrap();
        assert_eq!(idx.0, 0x14);
    }

    #[test]
    fn ignores_notification_and_response_for_another_software_id() {
        let transport = MockTransport::new();
        // Same device/feature/function, but first a notification (SWID 0), then
        // another client's response (SWID 2), then our actual response (SWID C).
        transport.push_response(vec![0x10, 0xFF, 0x00, 0x00, 0x00, 0, 0]);
        transport.push_response(vec![0x10, 0xFF, 0x00, 0x02, 0x00, 0, 0]);
        transport.push_response(vec![0x10, 0xFF, 0x00, SOFTWARE_ID, 0x14, 0, 0]);

        let device = HidppDevice::new(transport);
        let idx = device
            .get_feature_index(FeatureCode::OnboardProfiles)
            .unwrap();
        assert_eq!(idx.0, 0x14);
    }

    #[test]
    fn ignores_foreign_error_and_reads_our_error_code() {
        let transport = MockTransport::new();
        // Foreign error uses SWID 2; our error must use SWID C. On the wire,
        // buf[3] is the original feature, buf[4] the function/SWID and buf[5]
        // the HID++ error code.
        transport.push_response(vec![0x10, 0xFF, 0xFF, 0x00, 0x02, 0x09, 0x00]);
        transport.push_response(vec![0x10, 0xFF, 0xFF, 0x00, SOFTWARE_ID, 0x07, 0x00]);

        let device = HidppDevice::new(transport);
        let result = device.get_feature_index(FeatureCode::OnboardProfiles);
        assert!(matches!(
            result,
            Err(HidppError::DeviceError {
                feature_index: 0,
                error_code: 7
            })
        ));
    }

    #[test]
    fn feature_not_supported_when_index_zero() {
        let transport = MockTransport::new();
        // IRoot returns index 0x00 = not present
        transport.push_response(make_short_response(0x00, 0x00, [0x00, 0x00, 0x00, 0x00]));

        let device = HidppDevice::new(transport);
        let result = device.get_feature_index(FeatureCode::AdjustableDpi);
        assert!(matches!(
            result,
            Err(HidppError::FeatureNotSupported { .. })
        ));
    }
}
