open Operation;
open Helpers;

[@deriving yojson]
type t = {
  // TODO: validate this hash on yojson
  // TODO: what if block hash was a merkle tree of previous_hash + state_root_hash + block_data
  // block header
  // sha256(state_root_hash + payload_hash)
  hash: BLAKE2B.t,
  // TODO: is it okay to payload_hash to appears on both sides?
  // sha256(json of all fields including payload hash)
  payload_hash: BLAKE2B.t,
  state_root_hash: BLAKE2B.t,
  previous_hash: BLAKE2B.t,
  // block data
  author: Address.t,
  // TODO: do we need a block_height? What is the tradeoffs?
  // TODO: maybe it should be only for internal pagination and stuff like this
  block_height: int64,
  main_chain_ops: list(Main_chain.t),
  side_chain_ops: list(Side_chain.Self_signed.t),
};

let (hash, verify) = {
  /* TODO: this is bad name, it exists like this to prevent
     duplicating all this name parameters */

  let apply =
      (
        f,
        ~state_root_hash,
        ~previous_hash,
        ~author,
        ~block_height,
        ~main_chain_ops,
        ~side_chain_ops,
      ) => {
    let to_yojson = [%to_yojson:
      (
        BLAKE2B.t,
        BLAKE2B.t,
        // block data
        Address.t,
        int64,
        list(Main_chain.t),
        list(Side_chain.Self_signed.t),
      )
    ];
    let json =
      to_yojson((
        state_root_hash,
        previous_hash,
        author,
        block_height,
        main_chain_ops,
        side_chain_ops,
      ));
    let payload = Yojson.Safe.to_string(json);
    let payload_hash = BLAKE2B.hash(payload);
    // TODO: is it okay to have this string concatened here?
    // TODO: maybe should also be previous?

    let data_to_hash =
      BLAKE2B.(to_string(state_root_hash) ++ to_string(payload_hash));
    f(data_to_hash, payload_hash);
  };
  let hash =
    apply((data_to_hash, payload_hash) =>
      (BLAKE2B.hash(data_to_hash), payload_hash)
    );
  let verify = (~hash) =>
    apply((data_to_hash, _payload_hash) =>
      BLAKE2B.verify(~hash, data_to_hash)
    );
  (hash, verify);
};
// if needed we can export this, it's safe
let make =
    (
      ~state_root_hash,
      ~previous_hash,
      ~author,
      ~block_height,
      ~main_chain_ops,
      ~side_chain_ops,
    ) => {
  let (hash, payload_hash) =
    hash(
      ~state_root_hash,
      ~previous_hash,
      ~author,
      ~block_height,
      ~main_chain_ops,
      ~side_chain_ops,
    );
  {
    hash,
    payload_hash,
    previous_hash,

    state_root_hash,
    author,
    block_height,
    main_chain_ops,
    side_chain_ops,
  };
};

let of_yojson = json => {
  let.ok block = of_yojson(json);
  let.ok () =
    verify(
      ~hash=block.hash,
      ~state_root_hash=block.state_root_hash,
      ~previous_hash=block.previous_hash,
      ~author=block.author,
      ~block_height=block.block_height,
      ~main_chain_ops=block.main_chain_ops,
      ~side_chain_ops=block.side_chain_ops,
    )
      ? Ok() : Error("Invalid hash");
  Ok(block);
};

let compare = (a, b) => BLAKE2B.compare(a.hash, b.hash);

let genesis =
  make(
    ~previous_hash=BLAKE2B.Magic.hash("tuturu").hash,
    ~state_root_hash=BLAKE2B.Magic.hash("mayuushi-desu").hash,
    ~block_height=0L,
    ~main_chain_ops=[],
    ~side_chain_ops=[],
    ~author=Address.genesis_address,
  );

// TODO: move this to a global module
let state_root_hash_epoch = 6.0;
/** to prevent changing the validator just because of network jittering
    this introduce a delay between can receive a block with new state
    root hash and can produce that block

    10s choosen here but any reasonable time will make it */
let avoid_jitter = 1.0;
let _can_update_state_root_hash = state =>
  Unix.time() -. state.State.last_state_root_update >= state_root_hash_epoch;
let can_produce_with_new_state_root_hash = state =>
  Unix.time()
  -. state.State.last_state_root_update
  -. avoid_jitter >= state_root_hash_epoch;
let produce = (~state) =>
  make(
    ~previous_hash=state.State.last_block_hash,
    ~state_root_hash=
      can_produce_with_new_state_root_hash(state)
        ? State.hash(state).hash : state.state_root_hash,
    ~block_height=Int64.add(state.block_height, 1L),
  );

// TODO: this shouldn't be an open
open Signature.Make({
       type nonrec t = t;
       let hash = t => t.hash;
     });

let sign = (~key, t) => sign(~key, t).signature;
let verify = (~signature, t) => verify(~signature, t);
let verify_hash = (~signature, hash) => Signature.verify(~signature, hash);