const std = @import("std");

const U8 = u8;
const U16 = u16;
const U32 = u32;
const U64 = u64;
const ByteSequence = []u8;
const ByteArray32 = [32]u8;

const OpaqueHash = ByteArray32;
const TimeSlot = U32;
const ServiceId = U32;
const Gas = U64;
const ValidatorIndex = U16;
const CoreIndex = U16;
const TicketAttempt = u1; // as the range is 0..1

const BandersnatchKey = ByteArray32;
const Ed25519Key = ByteArray32;
const BandersnatchVrfSignature = [96]u8;
const BandersnatchRingSignature = [784]u8;
const Ed25519Signature = [64]u8;

const RefineContext = struct {
    anchor: OpaqueHash,
    state_root: OpaqueHash,
    beefy_root: OpaqueHash,
    lookup_anchor: OpaqueHash,
    lookup_anchor_slot: TimeSlot,
    prerequisite: ?OpaqueHash = null,
};

const ImportSpec = struct {
    tree_root: OpaqueHash,
    index: U16,
};

const ExtrinsicSpec = struct {
    hash: OpaqueHash,
    len: U32,
};

const Authorizer = struct {
    code_hash: OpaqueHash,
    params: ByteSequence,
};

const WorkItem = struct {
    service: ServiceId,
    code_hash: OpaqueHash,
    payload: ByteSequence,
    gas_limit: Gas,
    import_segments: []ImportSpec,
    extrinsic: []ExtrinsicSpec,
    export_count: U16,
};

const WorkPackage = struct {
    authorization: ByteSequence,
    auth_code_host: ServiceId,
    authorizer: Authorizer,
    context: RefineContext,
    items: [4]WorkItem,
};

const WorkExecResult = union(enum(u8)) {
    ok: ByteSequence = 0,
    out_of_gas: void = 1,
    panic: void = 2,
    bad_code: void = 3,
    code_oversize: void = 4,
};

const WorkResult = struct {
    service: ServiceId,
    code_hash: OpaqueHash,
    payload_hash: OpaqueHash,
    gas_ratio: Gas,
    result: WorkExecResult,
};

const WorkPackageSpec = struct {
    hash: OpaqueHash,
    len: U32,
    root: OpaqueHash,
    segments: OpaqueHash,
};

const WorkReport = struct {
    package_spec: WorkPackageSpec,
    context: RefineContext,
    core_index: CoreIndex,
    authorizer_hash: OpaqueHash,
    auth_output: ByteSequence,
    results: [4]WorkResult,
};

const EpochMark = struct {
    entropy: OpaqueHash,
    validators: []BandersnatchKey, // validators-count size
};

const TicketBody = struct {
    id: OpaqueHash,
    attempt: TicketAttempt,
};

const TicketsMark = []TicketBody; // epoch-length

const Header = struct {
    parent: OpaqueHash,
    parent_state_root: OpaqueHash,
    extrinsic_hash: OpaqueHash,
    slot: TimeSlot,
    epoch_mark: ?EpochMark = null,
    tickets_mark: ?TicketsMark = null,
    offenders_mark: []Ed25519Key,
    author_index: ValidatorIndex,
    entropy_source: BandersnatchVrfSignature,
    seal: BandersnatchVrfSignature,
};

const TicketEnvelope = struct {
    attempt: TicketAttempt,
    signature: BandersnatchRingSignature,
};

const TicketsExtrinsic = [16]TicketEnvelope;

const Judgement = struct {
    vote: bool,
    index: ValidatorIndex,
    signature: Ed25519Signature,
};

const Verdict = struct {
    target: OpaqueHash,
    age: U32,
    votes: []Judgement, // validators_super_majority
};

const Culprit = struct {
    target: OpaqueHash,
    key: Ed25519Key,
    signature: Ed25519Signature,
};

const Fault = struct {
    target: OpaqueHash,
    vote: bool,
    key: Ed25519Key,
    signature: Ed25519Signature,
};

const DisputesExtrinsic = struct {
    verdicts: []Verdict,
    culprits: []Culprit,
    faults: []Fault,
};

const Preimage = struct {
    requester: ServiceId,
    blob: ByteSequence,
};

const PreimagesExtrinsic = []Preimage;

const AvailAssurance = struct {
    anchor: OpaqueHash,
    bitfield: [1]u8, // avail_bitfield_bytes
    validator_index: ValidatorIndex,
    signature: Ed25519Signature,
};

const AssurancesExtrinsic = []AvailAssurance; // validators_count

const ValidatorSignature = struct {
    validator_index: ValidatorIndex,
    signature: Ed25519Signature,
};

const ReportGuarantee = struct {
    report: WorkReport,
    slot: TimeSlot,
    signatures: []ValidatorSignature,
};

const GuaranteesExtrinsic = []ReportGuarantee; // cores_count

const Extrinsic = struct {
    tickets: TicketsExtrinsic,
    disputes: DisputesExtrinsic,
    preimages: PreimagesExtrinsic,
    assurances: AssurancesExtrinsic,
    guarantees: GuaranteesExtrinsic,
};

const Block = struct {
    header: Header,
    extrinsic: Extrinsic,
};
