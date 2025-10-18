module collectivo::encrypter;

use collectivo::campaign::Campaign;
use collectivo::collectivo::AdminCap;

const EIdMismatch: u64 = 0;

entry fun seal_approve(id: vector<u8>, _cap: &AdminCap, campaign: &Campaign) {
    assert!(object::id_bytes(campaign) == id, EIdMismatch);
}
