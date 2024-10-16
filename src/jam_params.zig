pub const Params = struct {
    epoch_length: u32 = 600,
    // N: The number of ticket entries per validator
    max_ticket_entries_per_validator: u8 = 2,
    // Y: The number of slots into an epoch at which ticket submissions end
    ticket_submission_end_epoch_slot: u32 = 500,
    // K: The maximum tickets which may be submitted in a single extrinsic
    max_tickets_per_extrinsic: u32 = 16,
    // Validators count
    validators_count: u32,
    // Validators super majority
    validators_super_majority: u32,
    // Core-count
    core_count: u16,
};

pub const TINY_PARAMS = Params{
    .epoch_length = 12,
    .ticket_submission_end_epoch_slot = 10,
    .max_ticket_entries_per_validator = 2,
    .validators_count = 6,
    .validators_super_majority = 5,
    .core_count = 2,
};

pub const FULL_PARAMS = Params{
    .epoch_length = 600,
    .ticket_submission_end_epoch_slot = 500,
    .max_ticket_entries_per_validator = 2,
    .validators_count = 1023,
    .validators_super_majority = 683,
    .core_count = 341,
};
