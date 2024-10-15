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
};
