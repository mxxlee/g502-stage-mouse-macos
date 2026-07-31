use crate::protocol::feature::{FeatureCode, FeatureIndex};
use crate::protocol::message::HidppMessage;
use crate::transport::HidTransport;
use crate::{HidppDevice, HidppError};

/// Feature 0x8110 — raw physical mouse-button events.
///
/// The reported bit mask is independent of onboard profile assignments, so
/// buttons consumed as DPI/profile actions remain visible to host software.
pub struct MouseButtonSpy;

impl MouseButtonSpy {
    pub fn feature_index<T: HidTransport>(
        device: &HidppDevice<T>,
    ) -> Result<FeatureIndex, HidppError> {
        device.get_feature_index(FeatureCode::MouseButtonSpy)
    }

    pub fn button_count<T: HidTransport>(device: &HidppDevice<T>) -> Result<u8, HidppError> {
        let response = device.call_feature_short(FeatureCode::MouseButtonSpy, 0, [0, 0, 0, 0])?;
        Ok(response.params()[0])
    }

    pub fn start<T: HidTransport>(device: &HidppDevice<T>) -> Result<(), HidppError> {
        device.call_feature_short(FeatureCode::MouseButtonSpy, 1, [0, 0, 0, 0])?;
        Ok(())
    }

    pub fn stop<T: HidTransport>(device: &HidppDevice<T>) -> Result<(), HidppError> {
        device.call_feature_short(FeatureCode::MouseButtonSpy, 2, [0, 0, 0, 0])?;
        Ok(())
    }

    /// Parse event 0. Events use software ID 0 and contain a big-endian 16-bit
    /// mask in the first two parameter bytes.
    pub fn event_mask(feature: FeatureIndex, message: &HidppMessage) -> Option<u16> {
        if message.feature_index() != feature.0 || message.function_id() != 0 {
            return None;
        }
        let params = message.params();
        Some(u16::from_be_bytes([params[0], params[1]]))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::message::ShortMessage;

    #[test]
    fn parses_raw_button_event_mask() {
        let event = HidppMessage::Short(ShortMessage {
            device_id: 1,
            feature_index: 0x14,
            function_id: 0,
            params: [0x04, 0x08, 0, 0],
        });
        assert_eq!(
            MouseButtonSpy::event_mask(FeatureIndex(0x14), &event),
            Some(0x0408)
        );
    }

    #[test]
    fn rejects_non_event_software_id() {
        let response = HidppMessage::Short(ShortMessage {
            device_id: 1,
            feature_index: 0x14,
            function_id: 0x0C,
            params: [0, 1, 0, 0],
        });
        assert_eq!(
            MouseButtonSpy::event_mask(FeatureIndex(0x14), &response),
            None
        );
    }
}
