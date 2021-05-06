open Helpers;
open Protocol;

[@deriving yojson]
type identity = {
  key: Address.key,
  t: Address.t,
  uri: Uri.t,
};

[@deriving yojson]
type block_and_signatures = {
  // TODO: this should probably be a set
  signatures: Signatures.t,
  block: option(Block.t),
  hash: string,
};

[@deriving yojson]
type t = {
  identity,
  pending_side_ops: list(Operation.Side_chain.Self_signed.t),
  pending_main_ops: list(Operation.Main_chain.t),
  pending_blocks: String_map.t(block_and_signatures),
  pending_blocks_by_previous: String_map.t(list(block_and_signatures)),
  // TODO: make so that genesis happens through a different pipeline
  // TODO: then the CLI can inject block 2 instead, like if that was a stale
  last_signed_block: option(Block.t),
  applied_blocks: String_map.t(Block.t),
  applied_blocks_by_height: Int64_map.t(Block.t),
  protocol: Protocol.t,
  last_applied_block_timestamp: float,
  protocol_snapshots: Int64_map.t(string),
};

let make = (~identity) => {
  identity,
  pending_side_ops: [],
  pending_main_ops: [],
  pending_blocks: String_map.empty,
  pending_blocks_by_previous: String_map.empty,
  last_signed_block: None,
  applied_blocks: String_map.empty,
  applied_blocks_by_height: Int64_map.empty,
  last_applied_block_timestamp: 0.0,
  protocol: Protocol.empty,
  protocol_snapshots: Int64_map.empty,
};

let append_applied_block = (state, block) => {
  ...state,
  applied_blocks:
    state.applied_blocks |> String_map.add(block.Block.hash, block),
  applied_blocks_by_height:
    state.applied_blocks_by_height
    |> Int64_map.add(block.Block.block_height, block),
};
let append_snapshot = state => {
  let protocol = state.protocol;
  let snapshot =
    // TODO: this clearly is dumb and slow;
    SHA256.hash(protocol)
    |> SHA256.to_yojson(Protocol.to_yojson)
    |> Yojson.Safe.pretty_to_string;
  let protocol_snapshots =
    state.protocol_snapshots |> Int64_map.add(protocol.block_height, snapshot);
  {...state, protocol_snapshots};
};
let apply_block = (state, block) => {
  let.ok protocol = apply_block(state.protocol, block);
  let state = {...state, protocol};
  let state = append_applied_block(state, block);
  // TODO: magic number
  let state =
    Int64.rem(protocol.block_height, 600L) == 0L
      ? append_snapshot(state) : state;

  Ok(state);
};
