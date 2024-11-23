const std = @import("std");
const Allocator = std.mem.Allocator;

// Import system wide types
const types = @import("../types.zig");

/// Represents a Safrole state of the system as referenced in the GP γ.
pub const State = struct {
    /// τ: The most recent block's timeslot, crucial for maintaining the temporal
    /// context in block production.
    tau: types.TimeSlot,

    /// η: The entropy accumulator, which contributes to the system's randomness
    /// and is updated with each block.
    eta: types.Eta,

    /// λ: Validator keys and metadata from the previous epoch, essential for
    /// ensuring continuity and validating current operations.
    lambda: types.Lambda,

    /// κ: Validator keys and metadata that are currently active, representing the
    /// validators responsible for the current epoch.
    kappa: types.Kappa,

    /// γₖ: The keys for the validators of the next epoch, which help in planning
    /// the upcoming validation process.
    gamma_k: types.GammaK,

    /// ι: Validator keys and metadata to be drawn from next, which indicates the
    /// future state and validators likely to be active.
    iota: types.Iota,

    /// γₐ: The sealing lottery ticket accumulator, part of the process ensuring
    /// randomness and fairness in block sealing.
    gamma_a: types.GammaA,

    /// γₛ: the current epoch’s slot-sealer series, which is either a
    // full complement of E tickets or, in the case of a fallback
    // mode, a series of E Bandersnatch keys
    gamma_s: types.GammaS,

    /// γ𝑧: The Bandersnatch root for the current epoch’s ticket submissions,
    /// which is a cryptographic commitment to the current state of ticket
    /// submissions.
    gamma_z: types.GammaZ,

    /// Frees all allocated memory in the State struct.
    pub fn deinit(self: State, allocator: Allocator) void {
        self.lambda.deinit(allocator);
        self.kappa.deinit(allocator);
        self.gamma_k.deinit(allocator);
        self.iota.deinit(allocator);

        allocator.free(self.gamma_a);

        self.gamma_s.deinit(allocator);
    }

    /// Implement the default format function
    pub fn format(
        self: State,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try @import("types/format.zig").formatState(self, writer);
    }

    /// Creates a deep clone of the State struct.
    pub fn deepClone(self: *const State, allocator: Allocator) !State {
        return State{
            .tau = self.tau,
            .eta = self.eta,
            .lambda = try self.lambda.deepClone(allocator),
            .kappa = try self.kappa.deepClone(allocator),
            .gamma_k = try self.gamma_k.deepClone(allocator),
            .iota = try self.iota.deepClone(allocator),
            .gamma_a = try allocator.dupe(types.TicketBody, self.gamma_a),
            .gamma_s = try self.gamma_s.deepClone(allocator),
            .gamma_z = self.gamma_z,
        };
    }
};
