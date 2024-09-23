use ark_ec_vrfs::{
    prelude::ark_serialize::CanonicalDeserialize, suites::bandersnatch::edwards as bandersnatch,
};
use bandersnatch::Public;
use thiserror::Error;

use crate::ring_vrf::{
    context::ring_context,
    types::{vrf_input_point, RingCommitment, RingVrfSignature},
};

use super::context::RingContextError;

/// Verify based on Commitment
pub struct Commitment {
    pub commitment: RingCommitment,
    pub ring_size: usize,
}

#[derive(Error, Debug)]
pub enum Error {
    #[error("Signature verification failed")]
    SignatureVerificationFailed,
    #[error("Deserialization error")]
    DeserializationError,
    #[error("Invalid VRF input point")]
    VrfInputPointError,
    #[error(transparent)]
    RingContextError(#[from] RingContextError),
}

impl Commitment {
    pub fn new(commitment: RingCommitment, ring_size: usize) -> Self {
        Self {
            commitment,
            ring_size,
        }
    }

    pub fn ring_vrf_verify(
        &self,
        vrf_input_data: &[u8],
        aux_data: &[u8],
        signature: &[u8],
    ) -> Result<[u8; 32], Error> {
        use ark_ec_vrfs::ring::Verifier as _;

        let signature = RingVrfSignature::deserialize_compressed(signature)
            .map_err(|_| Error::DeserializationError)?;

        let input = vrf_input_point(vrf_input_data).ok_or(Error::VrfInputPointError)?;
        let output = signature.output;

        let ring_ctx = ring_context(self.ring_size)?;
        let verifier_key = ring_ctx.verifier_key_from_commitment(self.commitment.clone());
        let verifier = ring_ctx.verifier(verifier_key);
        if Public::verify(input, output, aux_data, &signature.proof, &verifier).is_err() {
            return Err(Error::SignatureVerificationFailed);
        }

        let vrf_output_hash: [u8; 32] = output.hash()[..32]
            .try_into()
            .expect("VRF output hash should be 32 bytes");
        Ok(vrf_output_hash)
    }
}
