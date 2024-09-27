pub const Instruction = enum(u8) {
    // A.5.1. Instructions without Arguments
    trap = 0,
    fallthrough = 17,

    // A.5.2. Instructions with Arguments of One Immediate
    ecalli = 78,

    // A.5.3. Instructions with Arguments of Two Immediates
    store_imm_u8 = 62,
    store_imm_u16 = 79,
    store_imm_u32 = 38,

    // A.5.4. Instructions with Arguments of One Offset
    jump = 5,

    // A.5.5. Instructions with Arguments of One Register & One Immediate
    jump_ind = 19,
    load_imm = 4,
    load_u8 = 60,
    load_i8 = 74,
    load_u16 = 76,
    load_i16 = 66,
    load_u32 = 10,
    store_u8 = 71,
    store_u16 = 69,
    store_u32 = 22,

    // A.5.6. Instructions with Arguments of One Register & Two Immediates
    store_imm_ind_u8 = 26,
    store_imm_ind_u16 = 54,
    store_imm_ind_u32 = 13,

    // A.5.7. Instructions with Arguments of One Register, One Immediate and One Offset
    load_imm_jump = 6,
    branch_eq_imm = 7,
    branch_ne_imm = 15,
    branch_lt_u_imm = 44,
    branch_le_u_imm = 59,
    branch_ge_u_imm = 52,
    branch_gt_u_imm = 50,
    branch_lt_s_imm = 32,
    branch_le_s_imm = 46,
    branch_ge_s_imm = 45,
    branch_gt_s_imm = 53,

    // A.5.8. Instructions with Arguments of Two Registers
    move_reg = 82,
    sbrk = 87,

    // A.5.9. Instructions with Arguments of Two Registers & One Immediate
    store_ind_u8 = 16,
    store_ind_u16 = 29,
    store_ind_u32 = 3,
    load_ind_u8 = 11,
    load_ind_i8 = 21,
    load_ind_u16 = 37,
    load_ind_i16 = 33,
    load_ind_u32 = 1,
    add_imm = 2,
    and_imm = 18,
    xor_imm = 31,
    or_imm = 49,
    mul_imm = 35,
    mul_upper_s_s_imm = 65,
    mul_upper_u_u_imm = 63,
    set_lt_u_imm = 27,
    set_lt_s_imm = 56,
    shlo_l_imm = 9,
    shlo_r_imm = 14,
    shar_r_imm = 25,
    neg_add_imm = 40,
    set_gt_u_imm = 39,
    set_gt_s_imm = 61,
    shlo_l_imm_alt = 75,
    shlo_r_imm_alt = 72,
    shar_r_imm_alt = 80,
    cmov_iz_imm = 85,
    cmov_nz_imm = 86,

    // A.5.10. Instructions with Arguments of Two Registers & One Offset
    branch_eq = 24,
    branch_ne = 30,
    branch_lt_u = 47,
    branch_lt_s = 48,
    branch_ge_u = 41,
    branch_ge_s = 43,

    // A.5.11. Instruction with Arguments of Two Registers and Two Immediates
    load_imm_jump_ind = 42,

    // A.5.12. Instructions with Arguments of Three Registers
    add = 8,
    sub = 20,
    @"and" = 23,
    xor = 28,
    @"or" = 12,
    mul = 34,
    mul_upper_s_s = 67,
    mul_upper_u_u = 57,
    mul_upper_s_u = 81,
    div_u = 68,
    div_s = 64,
    rem_u = 73,
    rem_s = 70,
    set_lt_u = 36,
    set_lt_s = 58,
    shlo_l = 55,
    shlo_r = 51,
    shar_r = 77,
    cmov_iz = 83,
    cmov_nz = 84,
};
