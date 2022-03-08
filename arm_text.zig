const types = @import("arm_text_types.zig");
const arm_format = @import("arm_text_arm_format.zig");
const thumb_format = @import("arm_text_thumb_format.zig");
const thumb32_format = @import("arm_text_thumb32_format.zig");

pub const TextError = types.TextError;
pub const formatArm = arm_format.formatArm;
pub const formatThumb16 = thumb_format.formatThumb16;
pub const formatThumb32 = thumb32_format.formatThumb32;
