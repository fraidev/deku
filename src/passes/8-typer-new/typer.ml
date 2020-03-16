open Trace

module I = Ast_core
module O = Ast_typed
open O.Combinators

module Environment = O.Environment

module Solver = Solver

type environment = Environment.t

module Errors = struct
  let unbound_type_variable (e:environment) (tv:I.type_variable) () =
    let title = (thunk "unbound type variable") in
    let message () = "" in
    let data = [
      ("variable" , fun () -> Format.asprintf "%a" I.PP.type_variable tv) ;
      (* TODO: types don't have srclocs for now. *)
      (* ("location" , fun () -> Format.asprintf "%a" Location.pp (n.location)) ; *)
      ("in" , fun () -> Format.asprintf "%a" Environment.PP.full_environment e)
    ] in
    error ~data title message ()

  let unbound_variable (e:environment) (n:I.expression_variable) (loc:Location.t) () =
    let name () = Format.asprintf "%a" I.PP.expression_variable n in
    let title = (thunk ("unbound variable "^(name ()))) in
    let message () = "" in
    let data = [
      ("variable" , name) ;
      ("environment" , fun () -> Format.asprintf "%a" Environment.PP.full_environment e) ;
      ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
    ] in
    error ~data title message ()

  let match_empty_variant : I.matching_expr -> Location.t -> unit -> _ =
    fun matching loc () ->
      let title = (thunk "match with no cases") in
      let message () = "" in
      let data = [
        ("variant" , fun () -> Format.asprintf "%a" I.PP.matching_type matching) ;
        ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
      ] in
      error ~data title message ()

  let match_missing_case : I.matching_expr -> Location.t -> unit -> _ =
    fun matching loc () ->
      let title = (thunk "missing case in match") in
      let message () = "" in
      let data = [
        ("variant" , fun () -> Format.asprintf "%a" I.PP.matching_type matching) ;
        ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
      ] in
      error ~data title message ()

  let match_redundant_case : I.matching_expr -> Location.t -> unit -> _ =
    fun matching loc () ->
      let title = (thunk "redundant case in match") in
      let message () = "" in
      let data = [
        ("variant" , fun () -> Format.asprintf "%a" I.PP.matching_type matching) ;
        ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
      ] in
      error ~data title message ()

  let unbound_constructor (e:environment) (c:I.constructor') (loc:Location.t) () =
    let title = (thunk "unbound constructor") in
    let message () = "" in
    let data = [
      ("constructor" , fun () -> Format.asprintf "%a" I.PP.constructor c) ;
      ("environment" , fun () -> Format.asprintf "%a" Environment.PP.full_environment e) ;
      ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
    ] in
    error ~data title message ()

  let wrong_arity (n:string) (expected:int) (actual:int) (loc : Location.t) () =
    let title () = "wrong arity" in
    let message () = "" in
    let data = [
      ("function" , fun () -> Format.asprintf "%s" n) ;
      ("expected" , fun () -> Format.asprintf "%d" expected) ;
      ("actual" , fun () -> Format.asprintf "%d" actual) ;
      ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
    ] in
    error ~data title message ()

  let match_tuple_wrong_arity (expected:'a list) (actual:'b list) (loc:Location.t) () =
    let title () = "matching tuple of different size" in
    let message () = "" in
    let data = [
      ("expected" , fun () -> Format.asprintf "%d" (List.length expected)) ;
      ("actual" , fun () -> Format.asprintf "%d" (List.length actual)) ;
      ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
    ] in
    error ~data title message ()

  (* TODO: this should be a trace_info? *)
  let program_error (p:I.program) () =
    let message () = "" in
    let title = (thunk "typing program") in
    let data = [
      ("program" , fun () -> Format.asprintf "%a" I.PP.program p)
    ] in
    error ~data title message ()

  let constant_declaration_error (name: I.expression_variable) (ae:I.expr) (expected: O.type_expression option) () =
    let title = (thunk "typing constant declaration") in
    let message () = "" in
    let data = [
      ("constant" , fun () -> Format.asprintf "%a" I.PP.expression_variable name) ; (* Todo : remove Stage_common*)
      ("expression" , fun () -> Format.asprintf "%a" I.PP.expression ae) ;
      ("expected" , fun () ->
          match expected with
            None -> "(no annotation for the expected type)"
          | Some expected -> Format.asprintf "%a" O.PP.type_expression expected) ;
      ("location" , fun () -> Format.asprintf "%a" Location.pp ae.location)
    ] in
    error ~data title message ()

  let match_error : ?msg:string -> expected: I.matching_expr -> actual: O.type_expression -> Location.t -> unit -> _ =
    fun ?(msg = "") ~expected ~actual loc () ->
      let title = (thunk "typing match") in
      let message () = msg in
      let data = [
        ("expected" , fun () -> Format.asprintf "%a" I.PP.matching_type expected);
        ("actual" , fun () -> Format.asprintf "%a" O.PP.type_expression actual) ;
        ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
      ] in
      error ~data title message ()

  (* let needs_annotation (e : I.expression) (case : string) () =
   *   let title = (thunk "this expression must be annotated with its type") in
   *   let message () = Format.asprintf "%s needs an annotation" case in
   *   let data = [
   *     ("expression" , fun () -> Format.asprintf "%a" I.PP.expression e) ;
   *     ("location" , fun () -> Format.asprintf "%a" Location.pp e.location)
   *   ] in
   *   error ~data title message () *)

  (* let type_error_approximate ?(msg="") ~(expected: string) ~(actual: O.type_value) ~(expression : I.expression) (loc:Location.t) () =
   *   let title = (thunk "type error") in
   *   let message () = msg in
   *   let data = [
   *     ("expected"   , fun () -> Format.asprintf "%s" expected);
   *     ("actual"     , fun () -> Format.asprintf "%a" O.PP.type_value actual);
   *     ("expression" , fun () -> Format.asprintf "%a" I.PP.expression expression) ;
   *     ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
   *   ] in
   *   error ~data title message () *)

  let type_error ?(msg="") ~(expected: O.type_expression) ~(actual: O.type_expression) ~(expression : I.expression) (loc:Location.t) () =
    let title = (thunk "type error") in
    let message () = msg in
    let data = [
      ("expected"   , fun () -> Format.asprintf "%a" O.PP.type_expression expected);
      ("actual"     , fun () -> Format.asprintf "%a" O.PP.type_expression actual);
      ("expression" , fun () -> Format.asprintf "%a" I.PP.expression expression) ;
      ("location" , fun () -> Format.asprintf "%a" Location.pp loc)
    ] in
    error ~data title message ()

end

open Errors

let swap (a,b) = ok (b,a)
(*
let rec type_program (p:I.program) : O.program result =
  let aux (e, acc:(environment * O.declaration Location.wrap list)) (d:I.declaration Location.wrap) =
    let%bind ed' = (bind_map_location (type_declaration e)) d in
    let loc : 'a . 'a Location.wrap -> _ -> _ = fun x v -> Location.wrap ~loc:x.location v in
    let (e', d') = Location.unwrap ed' in
    match d' with
    | None -> ok (e', acc)
    | Some d' -> ok (e', loc ed' d' :: acc)
  in
  let%bind (_, lst) =
    trace (fun () -> program_error p ()) @@
    bind_fold_list aux (Environment.full_empty, []) p in
  ok @@ List.rev lst
*)

(*
  Extract pairs of (name,type) in the declaration and add it to the environment
*)
let rec type_declaration env state : I.declaration -> (environment * Solver.state * O.declaration option) result = function
  | Declaration_type (type_name , type_expression) ->
    let%bind tv = evaluate_type env type_expression in
    let env' = Environment.add_type (type_name) tv env in
    ok (env', state , None)
  | Declaration_constant (name , tv_opt , inline, expression) -> (
    (*
      Determine the type of the expression and add it to the environment
    *)
      let%bind tv'_opt = bind_map_option (evaluate_type env) tv_opt in
      let%bind (ae' , state') =
        trace (constant_declaration_error name expression tv'_opt) @@
        type_expression env state expression in
      let env' = Environment.add_ez_ae name ae' env in
      ok (env', state' , Some (O.Declaration_constant (name, ae', inline, env') ))
    )

and type_match : environment -> Solver.state -> O.type_expression -> I.matching_expr -> I.expression -> Location.t -> (O.matching_expr * Solver.state) result =
  fun e state t i ae loc -> match i with
    | Match_bool {match_true ; match_false} ->
      let%bind _ =
        trace_strong (match_error ~expected:i ~actual:t loc)
        @@ get_t_bool t in
      let%bind (match_true , state') = type_expression e state match_true in
      let%bind (match_false , state'') = type_expression e state' match_false in
      ok (O.Match_bool {match_true ; match_false} , state'')
    | Match_option {match_none ; match_some} ->
      let%bind t_opt =
        trace_strong (match_error ~expected:i ~actual:t loc)
        @@ get_t_option t in
      let%bind (match_none , state') = type_expression e state match_none in
      let (n, b, _) = match_some in
      let e' = Environment.add_ez_binder n t_opt e in
      let%bind (b' , state'') = type_expression e' state' b in
      ok (O.Match_option {match_none ; match_some = (n, b', t_opt)} , state'')
    | Match_list {match_nil ; match_cons} ->
      let%bind t_elt =
        trace_strong (match_error ~expected:i ~actual:t loc)
        @@ get_t_list t in
      let%bind (match_nil , state') = type_expression e state match_nil in
      let (hd, tl, b, _) = match_cons in
      let e' = Environment.add_ez_binder hd t_elt e in
      let e' = Environment.add_ez_binder tl t e' in
      let%bind (b' , state'') = type_expression e' state' b in
      ok (O.Match_list {match_nil ; match_cons = (hd, tl, b',t)} , state'')
    | Match_tuple ((lst, b),_) ->
      let%bind t_tuple =
        trace_strong (match_error ~expected:i ~actual:t loc)
        @@ get_t_tuple t in
      let%bind lst' =
        generic_try (match_tuple_wrong_arity t_tuple lst loc)
        @@ (fun () -> List.combine lst t_tuple) in
      let aux prev (name, tv) = Environment.add_ez_binder name tv prev in
      let e' = List.fold_left aux e lst' in
      let%bind (b' , state') = type_expression e' state b in
      ok (O.Match_tuple ((lst, b'), t_tuple) , state')
    | Match_variant (lst,_) ->
      let%bind variant_opt =
        let aux acc ((constructor_name , _) , _) =
          let%bind (_ , variant) =
            trace_option (unbound_constructor e constructor_name loc) @@
            Environment.get_constructor constructor_name e in
          let%bind acc = match acc with
            | None -> ok (Some variant)
            | Some variant' -> (
                trace (type_error
                         ~msg:"in match variant"
                         ~expected:variant
                         ~actual:variant'
                         ~expression:ae
                         loc
                      ) @@
                Ast_typed.assert_type_expression_eq (variant , variant') >>? fun () ->
                ok (Some variant)
              ) in
          ok acc in
        trace (simple_info "in match variant") @@
        bind_fold_list aux None lst in
      let%bind variant =
        trace_option (match_empty_variant i loc) @@
        variant_opt in
      let%bind () =
        let%bind variant_cases' =
          trace (match_error ~expected:i ~actual:t loc)
          @@ Ast_typed.Combinators.get_t_sum variant in
        let variant_cases = List.map fst @@ I.CMap.to_kv_list variant_cases' in
        let match_cases = List.map (Function.compose fst fst) lst in
        let test_case = fun c ->
          Assert.assert_true (List.mem c match_cases)
        in
        let%bind () =
          trace_strong (match_missing_case i loc) @@
          bind_iter_list test_case variant_cases in
        let%bind () =
          trace_strong (match_redundant_case i loc) @@
          Assert.assert_true List.(length variant_cases = length match_cases) in
        ok ()
      in
      let%bind (state'' , lst') =
        let aux state ((constructor_name , name) , b) =
          let%bind (constructor , _) =
            trace_option (unbound_constructor e constructor_name loc) @@
            Environment.get_constructor constructor_name e in
          let e' = Environment.add_ez_binder name constructor e in
          let%bind (b' , state') = type_expression e' state b in
          ok (state' , ((constructor_name , name) , b'))
        in
        bind_fold_map_list aux state lst in
      ok (O.Match_variant (lst' , variant) , state'')

(*
  Recursively search the type_expression and return a result containing the
  type_value at the leaves
*)
and evaluate_type (e:environment) (t:I.type_expression) : O.type_expression result =
  let return tv' = ok (make_t tv' (Some t)) in
  match t.type_content with
  | T_arrow {type1;type2} ->
    let%bind type1 = evaluate_type e type1 in
    let%bind type2 = evaluate_type e type2 in
    return (T_arrow {type1;type2})
  | T_sum m ->
    let aux k v prev =
      let%bind prev' = prev in
      let%bind v' = evaluate_type e v in
      ok @@ I.CMap.add k v' prev'
    in
    let%bind m = I.CMap.fold aux m (ok I.CMap.empty) in
    return (T_sum m)
  | T_record m ->
    let aux k v prev =
      let%bind prev' = prev in
      let%bind v' = evaluate_type e v in
      ok @@ I.LMap.add k v' prev'
    in
    let%bind m = I.LMap.fold aux m (ok I.LMap.empty) in
    return (T_record m)
  | T_variable name ->
    let%bind tv =
      trace_option (unbound_type_variable e name)
      @@ Environment.get_type_opt (name) e in
    ok tv
  | T_constant cst ->
      return (T_constant cst)
  | T_operator opt ->
      let%bind opt = match opt with
        | TC_set s -> 
            let%bind s = evaluate_type e s in 
            ok @@ O.TC_set (s) 
        | TC_option o -> 
            let%bind o = evaluate_type e o in 
            ok @@ O.TC_option (o) 
        | TC_list l -> 
            let%bind l = evaluate_type e l in 
            ok @@ O.TC_list (l) 
        | TC_map (k,v) ->
            let%bind k = evaluate_type e k in 
            let%bind v = evaluate_type e v in 
            ok @@ O.TC_map (k,v) 
        | TC_big_map (k,v) ->
            let%bind k = evaluate_type e k in 
            let%bind v = evaluate_type e v in 
            ok @@ O.TC_big_map (k,v) 
        | TC_contract c ->
            let%bind c = evaluate_type e c in
            ok @@ O.TC_contract c
        | TC_arrow ( arg , ret ) ->
           let%bind arg' = evaluate_type e arg in
           let%bind ret' = evaluate_type e ret in
           ok @@ O.TC_arrow ( arg' , ret' )
        in
      return (T_operator (opt))

and type_expression : environment -> Solver.state -> ?tv_opt:O.type_expression -> I.expression -> (O.expression * Solver.state) result = fun e state ?tv_opt ae ->
  let () = ignore tv_opt in     (* For compatibility with the old typer's API, this argument can be removed once the new typer is used. *)
  let open Solver in
  let module L = Logger.Stateful() in
  let return : _ -> Solver.state -> _ -> _ (* return of type_expression *) = fun expr state constraints type_name ->
    let%bind new_state = aggregate_constraints state constraints in
    let tv = t_variable type_name () in
    let location = ae.location in
    let expr' = make_a_e ~location expr tv e in
    ok @@ (expr' , new_state) in
  let return_wrapped expr state (constraints , expr_type) = return expr state constraints expr_type in
  let main_error =
    let title () = "typing expression" in
    let content () = "" in
    let data = [
      ("expression" , fun () -> Format.asprintf "%a" I.PP.expression ae) ;
      ("location" , fun () -> Format.asprintf "%a" Location.pp @@ ae.location) ;
      ("misc" , fun () -> L.get ()) ;
    ] in
    error ~data title content in
  trace main_error @@
  match ae.expression_content with

  (* TODO: this file should take care only of the order in which program fragments
     are translated by Wrap.xyz

     TODO: produce an ordered list of sub-fragments, and use a common piece of code
     to actually perform the recursive calls *)

  (* Basic *)
  (* | E_failwith expr -> (
   *     let%bind (expr', state') = type_expression e state expr in
   *     let (constraints , expr_type) = Wrap.failwith_ () in
   *     let expr'' = e_failwith expr' in
   *     return expr''  state' constraints expr_type
   *   ) *)
  | E_variable name -> (
      let name'= name in
      let%bind (tv' : Environment.element) =
        trace_option (unbound_variable e name ae.location)
        @@ Environment.get_opt name' e in
      let (constraints , expr_type) = Wrap.variable name tv'.type_value in
      let expr' = e_variable name' in
      return expr' state constraints expr_type
    )
  | E_literal (Literal_bool b) -> (
      return_wrapped (e_bool b) state @@ Wrap.literal (t_bool ())
    )
  | E_literal (Literal_string s) -> (
      return_wrapped (e_string s) state @@ Wrap.literal (t_string ())
    )
  | E_literal (Literal_signature s) -> (
      return_wrapped (e_signature s) state @@ Wrap.literal (t_signature ())
    )
  | E_literal (Literal_key s) -> (
      return_wrapped (e_key s) state @@ Wrap.literal (t_key ())
    )
  | E_literal (Literal_key_hash s) -> (
      return_wrapped (e_key_hash s) state @@ Wrap.literal (t_key_hash ())
    )
  | E_literal (Literal_chain_id s) -> (
      return_wrapped (e_chain_id s) state @@ Wrap.literal (t_chain_id ())
    )
  | E_literal (Literal_bytes b) -> (
      return_wrapped (e_bytes b) state @@ Wrap.literal (t_bytes ())
    )
  | E_literal (Literal_int i) -> (
      return_wrapped (e_int i) state @@ Wrap.literal (t_int ())
    )
  | E_literal (Literal_nat n) -> (
      return_wrapped (e_nat n) state @@ Wrap.literal (t_nat ())
    )
  | E_literal (Literal_mutez t) -> (
      return_wrapped (e_mutez t) state @@ Wrap.literal (t_mutez ())
    )
  | E_literal (Literal_address a) -> (
      return_wrapped (e_address a) state @@ Wrap.literal (t_address ())
    )
  | E_literal (Literal_timestamp t) -> (
      return_wrapped (e_timestamp t) state @@ Wrap.literal (t_timestamp ())
    )
  | E_literal (Literal_operation o) -> (
      return_wrapped (e_operation o) state @@ Wrap.literal (t_operation ())
    )
  | E_literal (Literal_unit) -> (
      return_wrapped (e_unit ()) state @@ Wrap.literal (t_unit ())
    )
  | E_literal (Literal_void) -> (
      failwith "TODO: missing implementation for literal void"
    )
  | E_skip -> (
    (* E_skip just returns unit *)
    return_wrapped (e_unit ()) state @@ Wrap.literal (t_unit ())
    )
  (* | E_literal (Literal_string s) -> (
   *     L.log (Format.asprintf "literal_string option type: %a" PP_helpers.(option O.PP.type_expression) tv_opt) ;
   *     match Option.map Ast_typed.get_type' tv_opt with
   *     | Some (T_constant ("address" , [])) -> return (E_literal (Literal_address s)) (t_address ())
   *     | _ -> return (E_literal (Literal_string s)) (t_string ())
   *   ) *)
  | E_record_accessor {expr;label} -> (
      let%bind (base' , state') = type_expression e state expr in
      let wrapped = Wrap.access_label ~base:base'.type_expression ~label in
      return_wrapped (E_record_accessor {expr=base';label}) state' wrapped
    )

  (* Sum *)
  | E_constructor {constructor;element} ->
    let%bind (c_tv, sum_tv) =
      let error =
        let title () = "no such constructor" in
        let content () =
          Format.asprintf "%a in:\n%a\n"
            Stage_common.PP.constructor constructor
            O.Environment.PP.full_environment e
        in
        error title content in
      trace_option error @@
      Environment.get_constructor constructor e in
    let%bind (expr' , state') = type_expression e state element in
    let%bind _assert = O.assert_type_expression_eq (expr'.type_expression, c_tv) in
    let wrapped = Wrap.constructor expr'.type_expression c_tv sum_tv in
    return_wrapped (E_constructor {constructor; element=expr'}) state' wrapped

  (* Record *)
  | E_record m ->
    let aux (acc, state) k expr =
      let%bind (expr' , state') = type_expression e state expr in
      ok (I.LMap.add k expr' acc , state')
    in
    let%bind (m' , state') = Stage_common.Helpers.bind_fold_lmap aux (ok (I.LMap.empty , state)) m in
    let wrapped = Wrap.record (I.LMap.map get_type_expression m') in
    return_wrapped (E_record m') state' wrapped
  | E_record_update {record; path; update} ->
    let%bind (record, state) = type_expression e state record in
    let%bind (update,state) = type_expression e state update in
    let wrapped = get_type_expression record in
    let%bind (wrapped,tv) = 
      match wrapped.type_content with 
      | T_record record -> (
          let field_op = I.LMap.find_opt path record in
          match field_op with
          | Some tv -> ok (record,tv)
          | None -> failwith @@ Format.asprintf "field %a is not part of record" Stage_common.PP.label path
      )
      | _ -> failwith "Update an expression which is not a record"
    in
    let%bind () = O.assert_type_expression_eq (tv, get_type_expression update) in
    return_wrapped (E_record_update {record; path; update}) state (Wrap.record wrapped)
  (* Data-structure *)

(*
  | E_list lst ->
    let%bind lst' = bind_map_list (type_expression e) lst in
    let%bind tv =
      let aux opt c =
        match opt with
        | None -> ok (Some c)
        | Some c' ->
          let%bind _eq = Ast_typed.assert_type_value_eq (c, c') in
          ok (Some c') in
      let%bind init = match tv_opt with
        | None -> ok None
        | Some ty ->
          let%bind ty' = get_t_list ty in
          ok (Some ty') in
      let%bind ty =
        let%bind opt = bind_fold_list aux init
          @@ List.map get_type_annotation lst' in
        trace_option (needs_annotation ae "empty list") opt in
      ok (t_list ty ())
    in
    return (E_list lst') tv
  | E_set lst ->
    let%bind lst' = bind_map_list (type_expression e) lst in
    let%bind tv =
      let aux opt c =
        match opt with
        | None -> ok (Some c)
        | Some c' ->
          let%bind _eq = Ast_typed.assert_type_value_eq (c, c') in
          ok (Some c') in
      let%bind init = match tv_opt with
        | None -> ok None
        | Some ty ->
          let%bind ty' = get_t_set ty in
          ok (Some ty') in
      let%bind ty =
        let%bind opt = bind_fold_list aux init
          @@ List.map get_type_annotation lst' in
        trace_option (needs_annotation ae "empty set") opt in
      ok (t_set ty ())
    in
    return (E_set lst') tv
  | E_map lst ->
    let%bind lst' = bind_map_list (bind_map_pair (type_expression e)) lst in
    let%bind tv =
      let aux opt c =
        match opt with
        | None -> ok (Some c)
        | Some c' ->
          let%bind _eq = Ast_typed.assert_type_value_eq (c, c') in
          ok (Some c') in
      let%bind key_type =
        let%bind sub =
          bind_fold_list aux None
          @@ List.map get_type_annotation
          @@ List.map fst lst' in
        let%bind annot = bind_map_option get_t_map_key tv_opt in
        trace (simple_info "empty map expression without a type annotation") @@
        O.merge_annotation annot sub (needs_annotation ae "this map literal")
      in
      let%bind value_type =
        let%bind sub =
          bind_fold_list aux None
          @@ List.map get_type_annotation
          @@ List.map snd lst' in
        let%bind annot = bind_map_option get_t_map_value tv_opt in
        trace (simple_info "empty map expression without a type annotation") @@
        O.merge_annotation annot sub (needs_annotation ae "this map literal")
      in
      ok (t_map key_type value_type ())
    in
    return (E_map lst') tv
*)

  | E_list lst ->
    let%bind (state', lst') =
      bind_fold_map_list (fun state' elt -> type_expression e state' elt >>? swap) state lst in
    let wrapped = Wrap.list (List.map (fun x -> O.(x.type_expression)) lst') in
    return_wrapped (E_list lst') state' wrapped
  | E_set set ->
    let aux = fun state' elt -> type_expression e state' elt >>? swap in
    let%bind (state', set') =
      bind_fold_map_list aux state set in
    let wrapped = Wrap.set (List.map (fun x -> O.(x.type_expression)) set') in
    return_wrapped (E_set set') state' wrapped
  | E_map map ->
    let aux' state' elt = type_expression e state' elt >>? swap in
    let aux = fun state' elt -> bind_fold_map_pair aux' state' elt in
    let%bind (state', map') =
      bind_fold_map_list aux state map in
    let aux (x, y) = O.(x.type_expression , y.type_expression) in
    let wrapped = Wrap.map (List.map aux map') in
    return_wrapped (E_map map') state' wrapped

  (* | E_big_map lst ->
   *   let%bind lst' = bind_map_list (bind_map_pair (type_expression e)) lst in
   *   let%bind tv =
   *     let aux opt c =
   *       match opt with
   *       | None -> ok (Some c)
   *       | Some c' ->
   *         let%bind _eq = Ast_typed.assert_type_value_eq (c, c') in
   *         ok (Some c') in
   *     let%bind key_type =
   *       let%bind sub =
   *         bind_fold_list aux None
   *         @@ List.map get_type_annotation
   *         @@ List.map fst lst' in
   *       let%bind annot = bind_map_option get_t_big_map_key tv_opt in
   *       trace (simple_info "empty map expression without a type annotation") @@
   *       O.merge_annotation annot sub (needs_annotation ae "this map literal")
   *     in
   *     let%bind value_type =
   *       let%bind sub =
   *         bind_fold_list aux None
   *         @@ List.map get_type_annotation
   *         @@ List.map snd lst' in
   *       let%bind annot = bind_map_option get_t_big_map_value tv_opt in
   *       trace (simple_info "empty map expression without a type annotation") @@
   *       O.merge_annotation annot sub (needs_annotation ae "this map literal")
   *     in
   *     ok (t_big_map key_type value_type ())
   *   in
   *   return (E_big_map lst') tv *)
  | E_big_map big_map ->
    let aux' state' elt = type_expression e state' elt >>? swap in
    let aux = fun state' elt -> bind_fold_map_pair aux' state' elt in
    let%bind (state', big_map') =
      bind_fold_map_list aux state big_map in
    let aux (x, y) = O.(x.type_expression , y.type_expression) in
    let wrapped = Wrap.big_map (List.map aux big_map') in
    return_wrapped (E_big_map big_map') state' wrapped

  (* | E_lambda {
   *     binder ;
   *     input_type ;
   *     output_type ;
   *     result ;
   *   } -> (
   *     let%bind input_type =
   *       let%bind input_type =
   *         (\* Hack to take care of let_in introduced by `simplify/cameligo.ml` in ECase's hack *\)
   *         let default_action e () = fail @@ (needs_annotation e "the returned value") in
   *         match input_type with
   *         | Some ty -> ok ty
   *         | None -> (
   *             match result.expression with
   *             | I.E_let_in li -> (
   *                 match li.rhs.expression with
   *                 | I.E_variable name when name = (fst binder) -> (
   *                     match snd li.binder with
   *                     | Some ty -> ok ty
   *                     | None -> default_action li.rhs ()
   *                   )
   *                 | _ -> default_action li.rhs ()
   *               )
   *             | _ -> default_action result ()
   *           )
   *       in
   *       evaluate_type e input_type in
   *     let%bind output_type =
   *       bind_map_option (evaluate_type e) output_type
   *     in
   *     let e' = Environment.add_ez_binder (fst binder) input_type e in
   *     let%bind body = type_expression ?tv_opt:output_type e' result in
   *     let output_type = body.type_annotation in
   *     return (E_lambda {binder = fst binder ; body}) (t_function input_type output_type ())
   *   ) *)

  (* | E_constant (name, lst) ->
   *   let%bind lst' = bind_list @@ List.map (type_expression e) lst in
   *   let tv_lst = List.map get_type_annotation lst' in
   *   let%bind (name', tv) =
   *     type_constant name tv_lst tv_opt ae.location in
   *   return (E_constant (name' , lst')) tv *)
  | E_application {expr1;expr2} ->
    let%bind (f' , state') = type_expression e state expr1 in
    let%bind (arg , state'') = type_expression e state' expr2 in
    let wrapped = Wrap.application f'.type_expression arg.type_expression in
    return_wrapped (E_application {expr1=f';expr2=arg}) state'' wrapped

  (* | E_look_up dsi ->
   *   let%bind (ds, ind) = bind_map_pair (type_expression e) dsi in
   *   let%bind (src, dst) = bind_map_or (get_t_map , get_t_big_map) ds.type_annotation in
   *   let%bind _ = O.assert_type_value_eq (ind.type_annotation, src) in
   *   return (E_look_up (ds , ind)) (t_option dst ()) *)

  | E_look_up dsi ->
    let aux' state' elt = type_expression e state' elt >>? swap in
    let%bind (state'' , (ds , ind)) = bind_fold_map_pair aux' state dsi in
    let wrapped = Wrap.look_up ds.type_expression ind.type_expression in
    return_wrapped (E_look_up (ds , ind)) state'' wrapped

  (* Advanced *)
  (* | E_matching (ex, m) -> (
   *     let%bind ex' = type_expression e ex in
   *     let%bind m' = type_match (type_expression ?tv_opt:None) e ex'.type_annotation m ae ae.location in
   *     let tvs =
   *       let aux (cur:O.value O.matching) =
   *         match cur with
   *         | Match_bool { match_true ; match_false } -> [ match_true ; match_false ]
   *         | Match_list { match_nil ; match_cons = ((_ , _) , match_cons) } -> [ match_nil ; match_cons ]
   *         | Match_option { match_none ; match_some = (_ , match_some) } -> [ match_none ; match_some ]
   *         | Match_tuple (_ , match_tuple) -> [ match_tuple ]
   *         | Match_variant (lst , _) -> List.map snd lst in
   *       List.map get_type_annotation @@ aux m' in
   *     let aux prec cur =
   *       let%bind () =
   *         match prec with
   *         | None -> ok ()
   *         | Some cur' -> Ast_typed.assert_type_value_eq (cur , cur') in
   *       ok (Some cur) in
   *     let%bind tv_opt = bind_fold_list aux None tvs in
   *     let%bind tv =
   *       trace_option (match_empty_variant m ae.location) @@
   *       tv_opt in
   *     return (O.E_matching (ex', m')) tv
   *   ) *)
  | E_let_in {let_binder ; rhs ; let_result; inline} ->
    let%bind rhs_tv_opt = bind_map_option (evaluate_type e) (snd let_binder) in
    (* TODO: the binder annotation should just be an annotation node *)
    let%bind (rhs , state') = type_expression e state rhs in
    let let_binder = fst let_binder in 
    let e' = Environment.add_ez_declaration (let_binder) rhs e in
    let%bind (let_result , state'') = type_expression e' state' let_result in
    let wrapped =
      Wrap.let_in rhs.type_expression rhs_tv_opt let_result.type_expression in
    return_wrapped (E_let_in {let_binder; rhs; let_result; inline}) state'' wrapped
  | E_ascription {anno_expr;type_annotation} ->
    let%bind tv = evaluate_type e type_annotation in
    let%bind (expr' , state') = type_expression e state anno_expr in
    let wrapped = Wrap.annotation expr'.type_expression tv
    (* TODO: we're probably discarding too much by using expr'.expression.
       Previously: {expr' with type_annotation = the_explicit_type_annotation}
       but then this case is not like the others and doesn't call return_wrapped,
       which might do some necessary work *)
    in return_wrapped expr'.expression_content state' wrapped

  | E_matching {matchee;cases} -> (
      let%bind (ex' , state') = type_expression e state matchee in
      let%bind (m' , state'') = type_match e state' ex'.type_expression cases ae ae.location in
      let tvs =
        let aux (cur:(O.expression, O.type_expression) O.matching_content) =
          match cur with
          | Match_bool { match_true ; match_false } -> [ match_true ; match_false ]
          | Match_list { match_nil ; match_cons = (_ , _ , match_cons, _) } -> [ match_nil ; match_cons ]
          | Match_option { match_none ; match_some = (_ , match_some, _) } -> [ match_none ; match_some ]
          | Match_tuple ((_ , match_tuple), _) -> [ match_tuple ]
          | Match_variant (lst , _) -> List.map snd lst in
        List.map get_type_expression @@ aux m' in
      let%bind () = match tvs with
          [] -> fail @@ match_empty_variant cases ae.location
        | _ -> ok () in
      (* constraints:
         all the items of tvs should be equal to the first one
         result = first item of tvs
      *)
      let wrapped = Wrap.matching tvs in
      return_wrapped (O.E_matching {matchee=ex';cases=m'}) state'' wrapped
    )

  (* match m with *)
  (* Special case for assert-like failwiths. TODO: CLEAN THIS. *)
  (* | I.Match_bool { match_false ; match_true } when I.is_e_failwith match_true -> ( *)
  (*     let%bind fw = I.get_e_failwith match_true in *)
  (*     let%bind fw' = type_expression e fw in *)
  (*     let%bind mf' = type_expression e match_false in *)
  (*     let t = get_type_annotation ex' in *)
  (*     let%bind () = *)
  (*       trace_strong (match_error ~expected:m ~actual:t ae.location) *)
  (*       @@ assert_t_bool t in *)
  (*     let%bind () = *)
  (*       trace_strong (match_error *)
  (*                       ~msg:"matching not-unit on an assert" *)
  (*                       ~expected:m *)
  (*                       ~actual:t *)
  (*                       ae.location) *)
  (*       @@ assert_t_unit (get_type_annotation mf') in *)
  (*     let mt' = make_a_e *)
  (*         (E_constant ("ASSERT_INFERRED" , [ex' ; fw'])) *)
  (*         (t_unit ()) *)
  (*         e *)
  (*     in *)
  (*     let m' = O.Match_bool { match_true = mt' ; match_false = mf' } in *)
  (*     return (O.E_matching (ex' , m')) (t_unit ()) *)
  (*   ) *)
  (* | _ -> ( … ) *)


  | E_lambda lambda -> 
    let%bind (lambda,state',wrapped) = type_lambda e state lambda in
    return_wrapped (E_lambda lambda) (* TODO: is the type of the entire lambda enough to access the input_type=fresh; ? *)
        state' wrapped
  | E_recursive {fun_name;fun_type;lambda} ->
    let%bind fun_type = evaluate_type e fun_type in
    let e = Environment.add_ez_binder fun_name fun_type e in
    let%bind (lambda,state,_) = type_lambda e state lambda in
    let wrapped = Wrap.recursive fun_type in
    return_wrapped (E_recursive {fun_name;fun_type;lambda}) state wrapped

  | E_constant {cons_name=name; arguments=lst} ->
    let () = ignore (name , lst) in
    let%bind t = Operators.Typer.Operators_types.constant_type name in
    let aux acc expr =
      let (lst , state) = acc in
      let%bind (expr, state') = type_expression e state expr in
      ok (expr::lst , state') in
    let%bind (lst , state') = bind_fold_list aux ([], state) lst in
    let lst_annot = List.map (fun (x : O.expression) -> x.type_expression) lst in
    let wrapped = Wrap.constant t lst_annot in
    return_wrapped
      (E_constant {cons_name=name;arguments=lst})
      state' wrapped
      (*
      let%bind lst' = bind_list @@ List.map (type_expression e) lst in
      let tv_lst = List.map get_type_annotation lst' in
      let%bind (name', tv) =
        type_constant name tv_lst tv_opt ae.location in
      return (E_constant (name' , lst')) tv
    *)
and type_lambda e state {
      binder ;
      input_type ;
      output_type ;
      result ;
    } =
      let%bind input_type' = bind_map_option (evaluate_type e) input_type in
      let%bind output_type' = bind_map_option (evaluate_type e) output_type in

      let fresh : O.type_expression = t_variable (Solver.Wrap.fresh_binder ()) () in
      let e' = Environment.add_ez_binder (binder) fresh e in

      let%bind (result , state') = type_expression e' state result in
      let () = Printf.printf "this does not make use of the typed body, this code sounds buggy." in
      let wrapped = Solver.Wrap.lambda fresh input_type' output_type' in
      ok (({binder;result}:O.lambda),state',wrapped)
(* Advanced *)

and type_constant (name:I.constant') (lst:O.type_expression list) (tv_opt:O.type_expression option) : (O.constant' * O.type_expression) result =
  let%bind typer = Operators.Typer.constant_typers name in
  let%bind tv = typer lst tv_opt in
  ok(name, tv)

let untype_type_value (t:O.type_expression) : (I.type_expression) result =
  match t.type_meta with
  | Some s -> ok s
  | _ -> fail @@ internal_assertion_failure "trying to untype generated type"
(* let type_statement : environment -> I.declaration -> Solver.state -> (environment * O.declaration * Solver.state) result = fun env declaration state -> *)
(*   match declaration with *)
(*   | I.Declaration_type td -> ( *)
(*       let%bind (env', state', declaration') = type_declaration env state td in *)
(*       let%bind toto = Solver.aggregate_constraints state' constraints in *)
(*       let declaration' = match declaration' with None -> Pervasives.failwith "TODO" | Some x -> x in *)
(*       ok (env' , declaration' , toto) *)
(*     ) *)
(*   | I.Declaration_constant ((_ , _ , expr) as cd) -> ( *)
(*       let%bind state' = type_expression expr in *)
(*       let constraints = constant_declaration cd in *)
(*       Solver.aggregate_constraints state' constraints *)
(*     ) *)

(* TODO: we ended up with two versions of type_program… ??? *)

(*
Apply type_declaration on all the node of the AST_core from the root p
*)
let type_program_returns_state ((env, state, p) : environment * Solver.state * I.program) : (environment * Solver.state * O.program) result =
  let aux ((e : environment), (s : Solver.state) , (ds : O.declaration Location.wrap list)) (d:I.declaration Location.wrap) =
    let%bind (e' , s' , d'_opt) = type_declaration e s (Location.unwrap d) in
    let ds' = match d'_opt with
      | None -> ds
      | Some d' -> ds @ [Location.wrap ~loc:(Location.get_location d) d'] (* take O(n) insted of O(1) *)
    in
    ok (e' , s' , ds')
  in
  let%bind (env' , state' , declarations) =
    trace (fun () -> program_error p ()) @@
    bind_fold_list aux (env , state , []) p in
  let () = ignore (env' , state') in
  ok (env', state', declarations)

let type_and_subst_xyz (env_state_node : environment * Solver.state * 'a) (apply_substs : 'b Typesystem.Misc.Substitution.Pattern.w) (type_xyz_returns_state : (environment * Solver.state * 'a) -> (environment * Solver.state * 'b) Trace.result) : ('b * Solver.state) result =
  let%bind (env, state, program) = type_xyz_returns_state env_state_node in
  let subst_all =
    let aliases = state.structured_dbs.aliases in
    let assignments = state.structured_dbs.assignments in
    let substs : variable: I.type_variable -> _ = fun ~variable ->
      to_option @@
      let%bind root =
        trace_option (simple_error (Format.asprintf "can't find alias root of variable %a" Var.pp variable)) @@
          (* TODO: after upgrading UnionFind, this will be an option, not an exception. *)
          try Some (Solver.UF.repr variable aliases) with Not_found -> None in
      let%bind assignment =
        trace_option (simple_error (Format.asprintf "can't find assignment for root %a" Var.pp root)) @@
          (Solver.TypeVariableMap.find_opt root assignments) in
      let Solver.{ tv ; c_tag ; tv_list } = assignment in
      let () = ignore tv (* I think there is an issue where the tv is stored twice (as a key and in the element itself) *) in
      let%bind (expr : O.type_content) = Typesystem.Core.type_expression'_of_simple_c_constant (c_tag , (List.map (fun s -> O.{ type_content = T_variable s ; type_meta = None }) tv_list)) in
      ok @@ expr
    in
    let p = apply_substs ~substs program in
    p in
  let%bind program = subst_all in
  let () = ignore env in        (* TODO: shouldn't we use the `env` somewhere? *)
  ok (program, state)

let type_program (p : I.program) : (O.program * Solver.state) result =
  let empty_env = Ast_typed.Environment.full_empty in
  let empty_state = Solver.initial_state in
  type_and_subst_xyz (empty_env , empty_state , p) Typesystem.Misc.Substitution.Pattern.s_program type_program_returns_state

let type_expression_returns_state : (environment * Solver.state * I.expression) -> (environment * Solver.state * O.expression) Trace.result =
  fun (env, state, e) ->
  let%bind (e , state) = type_expression env state e in
  ok (env, state, e)

let type_expression_subst (env : environment) (state : Solver.state) ?(tv_opt : O.type_expression option) (e : I.expression) : (O.expression * Solver.state) result =
  let () = ignore tv_opt in     (* For compatibility with the old typer's API, this argument can be removed once the new typer is used. *)
  type_and_subst_xyz (env , state , e) Typesystem.Misc.Substitution.Pattern.s_expression type_expression_returns_state

 (*
TODO: Similar to type_program but use a fold_map_list and List.fold_left and add element to the left or the list which gives a better complexity
 *)
let type_program' : I.program -> O.program result = fun p ->
  let initial_state = Solver.initial_state in
  let initial_env = Environment.full_empty in
  let aux (env, state) (statement : I.declaration Location.wrap) =
    let statement' = statement.wrap_content in (* TODO *)
    let%bind (env' , state' , declaration') = type_declaration env state statement' in
    let declaration'' = match declaration' with
        None -> None
      | Some x -> Some (Location.wrap ~loc:Location.(statement.location) x) in
    ok ((env' , state') , declaration'')
  in
  let%bind ((env' , state') , p') = bind_fold_map_list aux (initial_env, initial_state) p in
  let p' = List.fold_left (fun l e -> match e with None -> l | Some x -> x :: l) [] p' in

  (* here, maybe ensure that there are no invalid things in env' and state' ? *)
  let () = ignore (env' , state') in
  ok p'

(*
  Tranform a Ast_typed type_expression into an ast_core type_expression
*)
let rec untype_type_expression (t:O.type_expression) : (I.type_expression) result =
  (* TODO: or should we use t.core if present? *)
  let%bind t = match t.type_content with
  | O.T_sum x ->
    let%bind x' = Stage_common.Helpers.bind_map_cmap untype_type_expression x in
    ok @@ I.T_sum x'
  | O.T_record x ->
    let%bind x' = Stage_common.Helpers.bind_map_lmap untype_type_expression x in
    ok @@ I.T_record x'
  | O.T_constant (tag) ->
    ok @@ I.T_constant (tag)
  | O.T_variable (name) -> ok @@ I.T_variable (name) (* TODO: is this the right conversion? *)
  | O.T_arrow {type1;type2} ->
    let%bind type1 = untype_type_expression type1 in
    let%bind type2 = untype_type_expression type2 in
    ok @@ I.T_arrow {type1;type2}
  | O.T_operator (type_name) ->
      let%bind type_name = match type_name with
      | O.TC_option t -> 
         let%bind t' = untype_type_expression t in
         ok @@ I.TC_option t'
      | O.TC_list   t ->
         let%bind t' = untype_type_expression t in
         ok @@ I.TC_list t'
      | O.TC_set    t ->     
         let%bind t' = untype_type_expression t in
         ok @@ I.TC_set t'
      | O.TC_map   (k,v) ->     
         let%bind k = untype_type_expression k in
         let%bind v = untype_type_expression v in
         ok @@ I.TC_map (k,v)
      | O.TC_big_map (k,v) ->     
         let%bind k = untype_type_expression k in
         let%bind v = untype_type_expression v in
         ok @@ I.TC_big_map (k,v)
      | O.TC_arrow ( arg , ret ) ->
         let%bind arg' = untype_type_expression arg in
         let%bind ret' = untype_type_expression ret in
         ok @@ I.TC_arrow ( arg' , ret' )
      | O.TC_contract c->
         let%bind c = untype_type_expression c in
         ok @@ I.TC_contract c
      in
      ok @@ I.T_operator (type_name)
    in
  ok @@ I.make_t t

(* match t.core with *)
(* | Some s -> ok s *)
(* | _ -> fail @@ internal_assertion_failure "trying to untype generated type" *)


(*
  Tranform a Ast_typed literal into an ast_core literal
*)
let untype_literal (l:O.literal) : I.literal result =
  let open I in
  match l with
  | Literal_unit -> ok Literal_unit
  | Literal_void -> ok Literal_void
  | Literal_bool b -> ok (Literal_bool b)
  | Literal_nat n -> ok (Literal_nat n)
  | Literal_timestamp n -> ok (Literal_timestamp n)
  | Literal_mutez n -> ok (Literal_mutez n)
  | Literal_int n -> ok (Literal_int n)
  | Literal_string s -> ok (Literal_string s)
  | Literal_key s -> ok (Literal_key s)
  | Literal_key_hash s -> ok (Literal_key_hash s)
  | Literal_chain_id s -> ok (Literal_chain_id s)
  | Literal_signature s -> ok (Literal_signature s)
  | Literal_bytes b -> ok (Literal_bytes b)
  | Literal_address s -> ok (Literal_address s)
  | Literal_operation s -> ok (Literal_operation s)

(*
  Tranform a Ast_typed expression into an ast_core matching
*)
let rec untype_expression (e:O.expression) : (I.expression) result =
  let open I in
  let return e = ok e in
  match e.expression_content with
  | E_literal l ->
    let%bind l = untype_literal l in
    return (e_literal l)
  | E_constant {cons_name;arguments} ->
      let%bind lst' = bind_map_list untype_expression arguments in
      return (e_constant cons_name lst')
  | E_variable (n) ->
    return (e_variable (n))
  | E_application {expr1;expr2} ->
      let%bind f' = untype_expression expr1 in
      let%bind arg' = untype_expression expr2 in
      return (e_application f' arg')
  | E_lambda lambda ->
      let%bind lambda = untype_lambda e.type_expression lambda in
      let {binder;input_type;output_type;result} = lambda in
      return (e_lambda (binder) (input_type) (output_type) result)
  | E_constructor {constructor; element} ->
      let%bind p' = untype_expression element in
      let Constructor n = constructor in
      return (e_constructor n p')
  | E_record r ->
    let aux ( Label k ,v) = (k, v) in
    let r = Map.String.of_list @@ List.map aux (LMap.to_kv_list r) in
    let%bind r' = bind_smap
      @@ Map.String.map untype_expression r in
    return (e_record r')
  | E_record_accessor {expr; label} ->
    let%bind r' = untype_expression expr in
    let Label s = label in
    return (e_accessor r' s)
  | E_record_update {record; path; update} ->
    let%bind r' = untype_expression record in
    let%bind e = untype_expression update in 
    let Label l = path in
    return (e_update r' l e)
  | E_map m ->
    let%bind m' = bind_map_list (bind_map_pair untype_expression) m in
    return (e_map m')
  | E_big_map m ->
    let%bind m' = bind_map_list (bind_map_pair untype_expression) m in
    return (e_big_map m')
  | E_list lst ->
    let%bind lst' = bind_map_list untype_expression lst in
    return (e_list lst')
  | E_set lst ->
    let%bind lst' = bind_map_list untype_expression lst in
    return (e_set lst')
  | E_look_up dsi ->
    let%bind (a , b) = bind_map_pair untype_expression dsi in
    return (e_look_up a b)
  | E_matching {matchee;cases} ->
    let%bind ae' = untype_expression matchee in
    let%bind m' = untype_matching untype_expression cases in
    return (e_matching ae' m')
  (* | E_failwith ae ->
   *   let%bind ae' = untype_expression ae in
   *   return (e_failwith ae') *)
  | E_let_in {let_binder; rhs;let_result; inline} ->
    let%bind tv = untype_type_value rhs.type_expression in
    let%bind rhs = untype_expression rhs in
    let%bind result = untype_expression let_result in
    return (e_let_in (let_binder , (Some tv)) inline rhs result)
  | E_recursive {fun_name; fun_type; lambda} ->
      let%bind lambda = untype_lambda fun_type lambda in
      let%bind fun_type = untype_type_expression fun_type in
      return @@ e_recursive fun_name fun_type lambda

and untype_lambda ty {binder; result} : I.lambda result =
      let%bind io = get_t_function ty in
      let%bind (input_type , output_type) = bind_map_pair untype_type_value io in
      let%bind result = untype_expression result in
      ok ({binder;input_type = Some input_type; output_type = Some output_type; result}: I.lambda)

(*
  Tranform a Ast_typed matching into an ast_core matching
*)
and untype_matching : (O.expression -> I.expression result) -> O.matching_expr -> I.matching_expr result = fun f m ->
  let open I in
  match m with
  | Match_bool {match_true ; match_false} ->
      let%bind match_true = f match_true in
      let%bind match_false = f match_false in
      ok @@ Match_bool {match_true ; match_false}
  | Match_tuple ((lst, b),_) ->
      let%bind b = f b in
      ok @@ I.Match_tuple ((lst, b),[])
  | Match_option {match_none ; match_some = (v, some,_)} ->
      let%bind match_none = f match_none in
      let%bind some = f some in
      let match_some = v, some, () in
      ok @@ Match_option {match_none ; match_some}
  | Match_list {match_nil ; match_cons = (hd_name, tl_name, cons,_)} ->
      let%bind match_nil = f match_nil in
      let%bind cons = f cons in
      let match_cons = hd_name , tl_name , cons, () in
      ok @@ Match_list {match_nil ; match_cons}
  | Match_variant (lst , _) ->
      let aux ((a,b),c) =
        let%bind c' = f c in
        ok ((a,b),c') in
      let%bind lst' = bind_map_list aux lst in
      ok @@ Match_variant (lst',())
