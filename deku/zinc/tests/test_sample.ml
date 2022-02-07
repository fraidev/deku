[@@@warning "-40"]

open Zinc_utils
module Zinc_interpreter = Zinc_interpreter.Dummy
open Zinc_interpreter.Types
open Zinc_interpreter
open Zinc

let zinc =
  Zinc_types.Zinc.
    [
      Plain_old_data (Address "tz1TGu6TN5GSez2ndXXeDX6LgUDvLzPLqgYV");
      Core Grab;
      Core (Access 0);
      Domain_specific_operation Contract_opt;
      Core Grab;
      Core (Access 0);
      Adt
        (MatchVariant
           [|
             [Core Grab; Core (Access 0)];
             [
               Core Grab;
               Plain_old_data (String "Not a contract");
               Control_flow Failwith;
             ];
           |]);
      Core EndLet;
      Core Grab;
      Plain_old_data (String "my string");
      Plain_old_data
        (Key "edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav");
      Core (Access 0);
      Plain_old_data (Mutez (Z.of_int 10));
      Domain_specific_operation MakeTransaction;
      Adt (MakeRecord 3);
      Core Return;
    ]
  |> Zinc_types.Zinc.to_yojson

module Executor : Executor = struct
module Pack = struct
  type t = string option

  type result =
    | Int of Z.t
    | String of string
    | Bytes of bytes
    | Key of string
    | Key_hash of string
    | Address of string
    | List of result list
    | Error of string

  let int _ = None

  let string _ = None

  let bytes _ = None

  let list _ = None

  let key _ = None

  let key_hash _ = None

  let address _ = None

  let to_bytes _ = Bytes.empty

  let of_bytes _ = String "Error"
end

module Executor : Zinc_interpreter.Dummy.Executor = struct
  module Pack = Pack

  let get_contract_opt a = Some Contract.{address = a; entrypoint = None}

  let chain_id = "chain id goes here"

  let key_hash s = s ^ "hash"
end

let%expect_test _ =
  let open Interpreter in
  let zinc = Types.Zinc.of_yojson zinc |> Result.get_ok in
  let run_result = eval (module Executor) (initial_state zinc) in
  Types.Interpreter_output.to_string run_result |> print_endline ;
  [%expect
    {|
    (Success (
       [(NonliteralValue
           (Contract
              { address = "tz1TGu6TN5GSez2ndXXeDX6LgUDvLzPLqgYV";
                entrypoint = None }));
         (Z (Plain_old_data (Address "tz1TGu6TN5GSez2ndXXeDX6LgUDvLzPLqgYV")))],
       [(Record
           [|(NonliteralValue
                (Chain_operation
                   (Transaction ((Record [||]),
                      { address = "tz1TGu6TN5GSez2ndXXeDX6LgUDvLzPLqgYV";
                        entrypoint = None }
                      ))));
             (Z
                (Plain_old_data
                   (Key edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav)));
             (Z (Plain_old_data (String "my string")))|])
         ]
       )) |}]