open Helpers;
open Crypto;
open Tezos;

module Context = {
  type t = {
    rpc_node: Uri.t,
    secret: Secret.t,
    consensus_contract: Address.t,
    required_confirmations: int,
  };
};
module Run_contract = {
  [@deriving to_yojson]
  type input = {
    nonce: int,
    rpc_node: string,
    secret: string,
    confirmation: int,
    destination: string,
    entrypoint: string,
    payload: Yojson.Safe.t,
  };
  type output_data =
    | Applied({hash: string})
    | Failed({hash: string})
    | Skipped({hash: string})
    | Backtracked({hash: string})
    | Unknown({hash: string})
    | Error(string);
  type output = {
    nonce: int,
    data: output_data,
  };

  let nonce_level = ref(-1);
  let bump_nonce_level = () => {
    let nonce = nonce_level^;
    let nonce =
      if (nonce == 999) {
        0;
      } else {
        nonce_level^ + 1;
      };
    nonce_level := nonce;
    nonce;
  };

  module IntMap = Map.Make(Int);
  let nonce_resolutions: ref(IntMap.t(Lwt.u(output_data))) =
    ref(IntMap.empty);

  let output_of_yojson = json => {
    module T = {
      [@deriving of_yojson({strict: false})]
      type t = {
        status: string,
        nonce: int,
      }
      and finished = {hash: string}
      and error = {error: string};
    };
    let finished = make => {
      let.ok {hash} = T.finished_of_yojson(json);
      Ok(make(hash));
    };
    let.ok {status, nonce} = T.of_yojson(json);
    let.ok data =
      switch (status) {
      | "applied" => finished(hash => Applied({hash: hash}))
      | "failed" => finished(hash => Failed({hash: hash}))
      | "skipped" => finished(hash => Skipped({hash: hash}))
      | "backtracked" => finished(hash => Backtracked({hash: hash}))
      | "unknown" => finished(hash => Unknown({hash: hash}))
      | "error" =>
        let.ok {error} = T.error_of_yojson(json);
        Ok(Error(error));
      | _ => Error("invalid status")
      };
    Ok({nonce, data});
  };

  let run = (~data_folder, ~context, ~destination, ~entrypoint, ~payload) => {
    let nonce = bump_nonce_level();
    let input = {
      nonce,
      rpc_node: context.Context.rpc_node |> Uri.to_string,
      secret: context.secret |> Secret.to_string,
      confirmation: context.required_confirmations,
      destination: Address.to_string(destination),
      entrypoint,
      payload,
    };
    let (read_channel, write_channel) =
      Named_pipe.get_pipe_pair_channels(data_folder ++ "/tezos_interop");
    let input_str = Yojson.Safe.to_string(input_to_yojson(input));
    let.await () = Lwt_io.write(write_channel, input_str);
    let (promise, resolve) = Lwt.wait();
    // Results may come in out of order, thus we need to be sure to resolve
    // the promise with the correct result.
    nonce_resolutions := IntMap.add(nonce, resolve, nonce_resolutions^);
    Lwt.async(() => {
      // Responses are always <=98 bytes
      let.await output = Lwt_io.read(~count=100, read_channel);
      switch (Yojson.Safe.from_string(output) |> output_of_yojson) {
      | Ok({nonce, data}) =>
        Format.printf("Commit operation result: %s\n%!", output);
        let resolve = IntMap.find(nonce, nonce_resolutions^);
        Lwt.wakeup(resolve, data);
        nonce_resolutions := IntMap.remove(nonce, nonce_resolutions^);
        Lwt.return_unit;
      | Error(error) =>
        Format.eprintf("Error while parsing Taquito output: %s", error);
        // In the case of an error, we just let the promise go unresolved.
        // TODO: fix this to be more robust.
        Lwt.return_unit;
      };
    });
    promise;
  };
};

let michelson_of_yojson = json => {
  // TODO: do this without serializing
  let.ok json = Yojson.Safe.to_string(json) |> Data_encoding.Json.from_string;
  try(
    Ok(
      Tezos_micheline.Micheline.root(
        Data_encoding.Json.destruct(Pack.expr_encoding, json),
      ),
    )
  ) {
  | _ => Error("invalid json")
  };
};
type michelson =
  Tezos_micheline.Micheline.node(int, Pack.Michelson_v1_primitives.prim);
module Fetch_storage: {
  let run:
    (~rpc_node: Uri.t, ~confirmation: int, ~contract_address: Address.t) =>
    Lwt.t(result(michelson, string));
} = {
  [@deriving to_yojson]
  type input = {
    rpc_node: string,
    confirmation: int,
    contract_address: string,
  };
  let output_of_yojson = json => {
    module T = {
      [@deriving of_yojson({strict: false})]
      type t = {status: string}
      and finished = {storage: michelson}
      and error = {error: string};
    };
    let.ok {status} = T.of_yojson(json);
    switch (status) {
    | "success" =>
      let.ok {storage} = T.finished_of_yojson(json);
      Ok(storage);
    | "error" =>
      let.ok T.{error: errorMessage} = T.error_of_yojson(json);
      Error(errorMessage);
    | _ =>
      Error(
        "JSON output %s did not contain 'success' or 'error' for field `status`",
      )
    };
  };

  // TODO: stop hard coding this
  let command = "node";
  let file = {
    let.await (file, oc) = Lwt_io.open_temp_file(~suffix=".js", ());
    let.await () = Lwt_io.write(oc, [%blob "fetch_storage.bundle.js"]);
    await(file);
  };
  let file = Lwt_main.run(file);

  let run = (~rpc_node, ~confirmation, ~contract_address) => {
    let input = {
      rpc_node: Uri.to_string(rpc_node),
      confirmation,
      contract_address: Address.to_string(contract_address),
    };
    let.await output =
      Lwt_process.pmap(
        (command, [|command, file|]),
        Yojson.Safe.to_string(input_to_yojson(input)),
      );
    switch (Yojson.Safe.from_string(output) |> output_of_yojson) {
    | Ok(storage) => await(Ok(storage))
    | Error(error) => await(Error(error))
    };
  };
};

module Listen_transactions = {
  [@deriving of_yojson]
  type transaction = {
    entrypoint: string,
    value: michelson,
  };
  [@deriving of_yojson]
  type output = {
    hash: string,
    transactions: list(transaction),
  };
  module CLI = {
    [@deriving to_yojson]
    type input = {
      rpc_node: string,
      confirmation: int,
      destination: string,
    };
    let file = {
      let.await (file, oc) = Lwt_io.open_temp_file(~suffix=".js", ());
      let.await () =
        Lwt_io.write(oc, [%blob "listen_transactions.bundle.js"]);
      await(file);
    };
    let file = Lwt_main.run(file);

    let node = "node";
    let run = (~context, ~destination, ~on_message, ~on_fail) => {
      let send = (f, pr, data) => {
        let oc = pr#stdin;
        Lwt.finalize(() => f(oc, data), () => Lwt_io.close(oc));
      };

      let process = Lwt_process.open_process((node, [|node, file|]));
      let input =
        {
          rpc_node: Uri.to_string(context.Context.rpc_node),
          confirmation: context.required_confirmations,
          destination: Address.to_string(destination),
        }
        |> input_to_yojson
        |> Yojson.Safe.to_string;
      let on_fail = _exn => {
        // TODO: what to do with this exception
        // TODO: what to do with this status
        let.await _status = process#close;
        on_fail();
      };
      let.await () = send(Lwt_io.write, process, input);

      let rec read_line_until_fails = () =>
        Lwt.catch(
          () => {
            let.await line = Lwt_io.read_line(process#stdout);
            print_endline(line);
            Yojson.Safe.from_string(line)
            |> output_of_yojson
            |> Result.get_ok
            |> on_message;
            read_line_until_fails();
          },
          on_fail,
        );
      read_line_until_fails();
    };
  };

  let listen = (~context, ~destination, ~on_message) => {
    let rec start = () =>
      Lwt.catch(
        () => CLI.run(~context, ~destination, ~on_message, ~on_fail),
        // TODO: what to do with this exception?
        _exn => on_fail(),
      )
    and on_fail = () => start();
    Lwt.async(start);
  };
};
module Consensus = {
  let initialize_taquito = (~data_folder) => {
    let pipe_path = data_folder ++ "/tezos_interop";
    Named_pipe.make_pipe_pair(pipe_path);
    // TODO: this leaks the file as it needs to be removed when the app closes
    let js_file = {
      let.await (file, oc) = Lwt_io.open_temp_file(~suffix=".js", ());
      let.await () = Lwt_io.write(oc, [%blob "run_entrypoint.bundle.js"]);
      await(file);
    };
    let js_file = Lwt_main.run(js_file);
    let _pid =
      Unix.create_process(
        "node",
        [|"node", js_file, pipe_path|],
        Unix.stdin,
        Unix.stdout,
        Unix.stderr,
      );
    ();
  };

  open Pack;
  open Tezos_micheline;

  // TODO: how to test this?
  let commit_state_hash =
      (
        ~data_folder,
        ~context,
        ~block_height,
        ~block_payload_hash,
        ~state_hash,
        ~validators,
        ~signatures,
      ) => {
    module Payload = {
      [@deriving to_yojson]
      type t = {
        block_height: int64,
        block_payload_hash: BLAKE2B.t,
        signatures: list(option(string)),
        state_hash: BLAKE2B.t,
        validators: list(string),
        current_validator_keys: list(option(string)),
      };
    };
    open Payload;
    let (current_validator_keys, signatures) =
      List.map(
        signature =>
          switch (signature) {
          | Some((key, signature)) =>
            let key = Key.to_string(key);
            let signature = Signature.to_string(signature);
            (Some(key), Some(signature));
          | None => (None, None)
          },
        signatures,
      )
      |> List.split;
    let validators = List.map(Key_hash.to_string, validators);

    let payload = {
      block_height,
      block_payload_hash,
      signatures,
      state_hash,
      validators,
      current_validator_keys,
    };
    // TODO: what should this code do with the output? Retry?
    //      return back that it was a failure?
    let.await _ =
      Run_contract.run(
        ~data_folder,
        ~context,
        ~destination=context.Context.consensus_contract,
        ~entrypoint="update_root_hash",
        ~payload=Payload.to_yojson(payload),
      );
    await();
  };

  type transaction =
    | Deposit({
        ticket: Ticket_id.t,
        // TODO: proper type for amounts
        amount: Z.t,
        destination: Address.t,
      })
    | Update_root_hash(BLAKE2B.t);
  type operation = {
    hash: Operation_hash.t,
    transactions: list(transaction),
  };

  let parse_transaction = transaction =>
    switch (transaction.Listen_transactions.entrypoint, transaction.value) {
    | (
        "update_root_hash",
        Tezos_micheline.Micheline.Prim(
          _,
          Michelson_v1_primitives.D_Pair,
          [
            Prim(
              _,
              D_Pair,
              [
                Prim(
                  _,
                  D_Pair,
                  [Bytes(_, _block_hash), Int(_, _block_height)],
                  _,
                ),
                Prim(
                  _,
                  D_Pair,
                  [Bytes(_, _block_payload_hash), Int(_, _handles_hash)],
                  _,
                ),
              ],
              _,
            ),
            Prim(
              _,
              D_Pair,
              [
                Prim(_, D_Pair, [_signatures, Bytes(_, state_root_hash)], _),
                _,
              ],
              _,
            ),
          ],
          _,
        ),
      ) =>
      let.some state_root_hash =
        state_root_hash |> Bytes.to_string |> BLAKE2B.of_raw_string;
      Some(Update_root_hash(state_root_hash));
    | (
        "deposit",
        Micheline.Prim(
          _,
          Michelson_v1_primitives.D_Pair,
          [
            Bytes(_, destination),
            Prim(
              _,
              D_Pair,
              [
                Bytes(_, ticketer),
                Prim(_, D_Pair, [Bytes(_, data), Int(_, amount)], _),
              ],
              _,
            ),
          ],
          _,
        ),
      ) =>
      let.some destination =
        Data_encoding.Binary.of_bytes_opt(Address.encoding, destination);
      let.some ticketer =
        Data_encoding.Binary.of_bytes_opt(Address.encoding, ticketer);
      let ticket = Ticket_id.{ticketer, data};
      Some(Deposit({ticket, destination, amount}));
    | _ => None
    };
  let parse_operation = output => {
    let.some hash = Operation_hash.of_string(output.Listen_transactions.hash);
    let transactions =
      List.filter_map(parse_transaction, output.transactions);

    Some({hash, transactions});
  };
  let listen_operations = (~context, ~on_operation) => {
    let on_message = output =>
      switch (parse_operation(output)) {
      | Some(operation) => on_operation(operation)
      | None => ()
      };
    Listen_transactions.listen(
      ~context,
      ~destination=context.consensus_contract,
      ~on_message,
    );
  };
  let fetch_validators = (~context) => {
    let Context.{rpc_node, required_confirmations, consensus_contract, _} = context;
    let micheline_to_validators =
      fun
      | Ok(
          Micheline.Prim(
            _,
            Michelson_v1_primitives.D_Pair,
            [_, _, Seq(_, key_hashes)],
            _,
          ),
        ) => {
          List.fold_left_ok(
            (acc, k) =>
              switch (k) {
              | Micheline.String(_, k) =>
                switch (Key_hash.of_string(k)) {
                | Some(k) => Ok([k, ...acc])
                | None => Error("Failed to parse " ++ k)
                }
              | _ => Error("Some key_hash wasn't of type string")
              },
            [],
            List.rev(key_hashes),
          );
        }
      | Ok(_) => Error("Failed to parse storage micheline expression")
      | Error(msg) => Error(msg);
    let.await micheline_storage =
      Fetch_storage.run(
        ~confirmation=required_confirmations,
        ~rpc_node,
        ~contract_address=consensus_contract,
      );
    Lwt.return(micheline_to_validators(micheline_storage));
  };
};

module Discovery = {
  open Pack;

  let sign = (secret, ~nonce, uri) =>
    to_bytes(
      pair(
        int(Z.of_int64(nonce)),
        bytes(Bytes.of_string(Uri.to_string(uri))),
      ),
    )
    |> Bytes.to_string
    |> BLAKE2B.hash
    |> Signature.sign(secret);
};
