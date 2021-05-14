open Helpers;
open Protocol;

module Node = State;

let is_valid_signature = (~hash, ~signature) => {
  // TODO: check if it's made by a known validator, avoid noise
  let Networking.{key, signature} = signature;
  let.ok signed =
    Signed.verify(~key, ~signature, hash)
    |> Result.map_error(_ => `Invalid_signature);
  signed |> Multisig.of_signed |> Multisig.signatures |> List.nth(_, 0) |> ok;
};

let is_valid_block = (state, block) => {
  // TODO: check if it's made by a known validator?
  let is_all_operations_properly_signed = _block =>
    // TODO: move this out from of_yojson
    true;
  let.assert () = (
    "new block has a lower block height",
    block.Block.block_height >= state.Node.protocol.block_height,
  );

  // TODO: should we just ignore this operations?
  let.assert () = (
    "some operation in the block is not properly signed",
    is_all_operations_properly_signed(block),
  );

  Ok();
};

let is_next = (state, block) => Protocol.is_next(state.Node.protocol, block);

let has_next_block_to_apply = (state, ~hash) =>
  Block_pool.find_next_block_to_apply(~hash, state.Node.block_pool)
  |> Option.is_some;

let is_known_block = (state, ~hash) =>
  Option.is_some(Block_pool.find_block(state.Node.block_pool, ~hash));
let is_known_signature = (state, ~hash, ~signature) => {
  let.default () = false;
  let.some signatures =
    Block_pool.find_signatures(~hash, state.Node.block_pool);
  Some(Signatures.mem(signature, signatures));
};

let is_signed_by_self = (state, ~hash) => {
  // TODO: for the name of this function being correct we shuold check it recursively
  let.default () = false;
  let.some signatures =
    Block_pool.find_signatures(~hash, state.Node.block_pool);
  Some(Signatures.is_self_signed(signatures));
};
let get_current_block_producer = state =>
  if (state.Node.last_applied_block_timestamp == 0.0) {
    None;
  } else {
    // TODO: this is clearly dumb
    let rec next_until = (validators, diff) =>
      diff < 10.0
        ? validators : next_until(Validators.next(validators), diff -. 10.0);
    let diff = Unix.time() -. state.Node.last_applied_block_timestamp;
    let validators = next_until(state.protocol.validators, diff);
    Validators.current(validators);
  };

let is_current_producer = (state, ~key) => {
  let.default () = false;
  let.some current_producer = get_current_block_producer(state);
  Some(current_producer.address == key);
};

// TODO: bad naming
let is_signable = (state, block) =>
  Int64.add(state.Node.protocol.block_height, 1L) == block.Block.block_height
  && !is_signed_by_self(state, ~hash=block.hash)
  && is_current_producer(state, ~key=block.author)
  && !has_next_block_to_apply(state, ~hash=block.hash);

let sign = (~key, ~hash) =>
  Signed.sign(~key, hash)
  |> Multisig.of_signed
  |> Multisig.signatures
  |> List.nth(_, 0);

let produce_block = state =>
  Block.make(
    ~previous_hash=last_block_hash(state.Node.protocol),
    ~author=state.Node.identity.t,
    ~block_height=Int64.add(state.protocol.block_height, 1L),
    ~main_chain_ops=state.pending_main_ops,
    ~side_chain_ops=state.pending_side_ops,
  );

let is_valid_block_height = (state, block_height) =>
  block_height >= 1L && block_height <= state.Node.protocol.block_height;

// TODO: should also support valid blocks that were not applied yet
let find_applied_block_by_height = (state, block_height) =>
  Int64_map.find_opt(block_height, state.Node.applied_blocks_by_height);

let signatures_required = state => {
  let number_of_validators =
    Validators.validators(state.Node.protocol.validators) |> List.length;
  // TODO: properly filter and check signatures
  Float.(to_int(ceil(of_int(number_of_validators) *. (2.0 /. 3.0))));
};

// mutations
let append_signature = (state, update_state, ~hash, ~signature) => {
  let block_pool =
    Block_pool.append_signature(
      ~signatures_required=signatures_required(state),
      ~hash,
      signature,
      state.Node.block_pool,
    );
  update_state({...state, block_pool});
};

let add_block_to_pool = (state, update_state, block) => {
  let block_pool = Block_pool.append_block(block, state.Node.block_pool);
  update_state({...state, block_pool});
};

let apply_block = (state, update_state, block) => {
  let.ok state = Node.apply_block(state, block);
  Ok(update_state(state));
};

let clean = (state, update_state, block) => {
  // TODO: this is the dumbest piece of code that I could write
  let main_is_in_block = side_op =>
    block.Block.main_chain_ops |> List.exists(op => side_op == op);
  let side_is_in_block = side_op =>
    block.side_chain_ops |> List.exists(op => side_op == op);

  let pending_main_ops =
    state.Node.pending_main_ops |> List.filter(main_is_in_block);
  let pending_side_ops =
    state.pending_side_ops |> List.filter(side_is_in_block);
  // TODO: clean old blocks and old signatures
  update_state({
    ...state,
    pending_main_ops,
    pending_side_ops,
    last_applied_block_timestamp: Unix.time(),
  });
};

// networking functions

// TODO: maybe send to some specific nodes so that they should broadcast it?
// maybe have a random chance of re-broadcasting it to the network
let broadcast_signature = (state, ~hash, ~signature) =>
  Lwt.async(() =>
    Networking.broadcast_signature(
      state,
      {
        hash,
        signature:
          Multisig.{key: signature.key, signature: signature.signature},
      },
    )
  );
let broadcast_block_and_signature = (state, ~block, ~signature) =>
  Lwt.async(() => {
    let.await () = Lwt_unix.sleep(1.0);
    Networking.broadcast_block_and_signature(
      state,
      {
        block,
        signature:
          Multisig.{key: signature.key, signature: signature.signature},
      },
    );
  });