open! Ligo_helpers.Trace
open Mini_c
open Combinators

module AST = Ast_typed
open AST.Combinators

let list_of_map m = List.rev @@ Ligo_helpers.X_map.String.fold (fun _ v prev -> v :: prev) m []
let kv_list_of_map m = List.rev @@ Ligo_helpers.X_map.String.fold (fun k v prev -> (k, v) :: prev) m []
let map_of_kv_list lst =
  let open AST.SMap in
  List.fold_left (fun prev (k, v) -> add k v prev) empty lst

let rec translate_type (t:AST.type_value) : type_value result =
  match t.type_value with
  | T_constant ("bool", []) -> ok (T_base Base_bool)
  | T_constant ("int", []) -> ok (T_base Base_int)
  | T_constant ("string", []) -> ok (T_base Base_string)
  | T_constant ("unit", []) -> ok (T_base Base_unit)
  | T_constant ("map", [key;value]) ->
      let%bind kv' = bind_map_pair translate_type (key, value) in
      ok (T_map kv')
  | T_constant ("option", [o]) ->
      let%bind o' = translate_type o in
      ok (T_option o')
  | T_constant (name, _) -> fail (error "unrecognized constant" name)
  | T_sum m ->
      let node = Append_tree.of_list @@ list_of_map m in
      let aux a b : type_value result =
        let%bind a = a in
        let%bind b = b in
        ok (T_or (a, b))
      in
      Append_tree.fold_ne translate_type aux node
  | T_record m ->
      let node = Append_tree.of_list @@ list_of_map m in
      let aux a b : type_value result =
        let%bind a = a in
        let%bind b = b in
        ok (T_pair (a, b))
      in
      Append_tree.fold_ne translate_type aux node
  | T_tuple lst ->
      let node = Append_tree.of_list lst in
      let aux a b : type_value result =
        let%bind a = a in
        let%bind b = b in
        ok (T_pair (a, b))
      in
      Append_tree.fold_ne translate_type aux node
  | T_function (param, result) ->
      let%bind param' = translate_type param in
      let%bind result' = translate_type result in
      ok (T_function (param', result'))

let rec translate_block env (b:AST.block) : block result =
  let%bind (instructions, env') =
    let rec aux e acc lst = match lst with
      | [] -> ok (acc, e)
      | hd :: tl ->
          match%bind translate_instruction e hd with
          | Some ((_, e') as i) -> aux e'.post_environment (i :: acc) tl
          | None -> aux e acc tl
    in
    let%bind (lst, e) = aux env [] b in
    ok (List.rev lst, e)
  in
  ok (instructions, environment_wrap env env')

and translate_instruction (env:Environment.t) (i:AST.instruction) : statement option result =
  let return ?(env' = env) x : statement option result = ok (Some (x, environment_wrap env env')) in
  match i with
  | I_assignment {name;annotated_expression} ->
      let%bind (_, t, _) as expression = translate_annotated_expression env annotated_expression in
      let env' = Environment.add (name, t) env in
      return ~env' (Assignment (name, expression))
  | I_matching (expr, m) -> (
      let%bind expr' = translate_annotated_expression env expr in
      let env' = Environment.extend env in
      match m with
      | Match_bool {match_true ; match_false} -> (
          let%bind true_branch = translate_block env' match_true in
          let%bind false_branch = translate_block env' match_false in
          return (I_Cond (expr', true_branch, false_branch))
        )
      | Match_option {match_none ; match_some = ((name, t), sm)} -> (
          let%bind none_branch = translate_block env' match_none in
          let%bind some_branch =
            let%bind t' = translate_type t in
            let env' = Environment.add (name, t') env' in
            translate_block env' sm in
          return (If_None (expr', none_branch, (name, some_branch)))
        )
      | _ -> simple_fail "todo : match"
    )
  | I_loop (expr, body) ->
      let%bind expr' = translate_annotated_expression env expr in
      let%bind body' = translate_block env body in
      return (While (expr', body'))
  | I_skip -> ok None
  | I_fail _ -> simple_fail "todo : fail"

and translate_annotated_expression (env:Environment.t) (ae:AST.annotated_expression) : expression result =
  let%bind tv = translate_type ae.type_annotation in
  let return (expr, tv) = ok (expr, tv, env) in
  let f = translate_annotated_expression env in
  match ae.expression with
  | E_literal (Literal_bool b) -> ok (E_literal (D_bool b), tv, env)
  | E_literal (Literal_int n) -> ok (E_literal (D_int n), tv, env)
  | E_literal (Literal_nat n) -> ok (E_literal (D_nat n), tv, env)
  | E_literal (Literal_bytes s) -> ok (E_literal (D_bytes s), tv, env)
  | E_literal (Literal_string s) -> ok (E_literal (D_string s), tv, env)
  | E_literal Literal_unit -> ok (E_literal D_unit, tv, env)
  | E_variable name -> ok (E_variable name, tv, env)
  | E_application (a, b) ->
      let%bind a = translate_annotated_expression env a in
      let%bind b = translate_annotated_expression env b in
      ok (E_application (a, b), tv, env)
  | E_constructor (m, param) ->
      let%bind (param'_expr, param'_tv, _) = translate_annotated_expression env ae in
      let%bind map_tv = get_t_sum ae.type_annotation in
      let node_tv = Append_tree.of_list @@ kv_list_of_map map_tv in
      let%bind ae' =
        let leaf (k, tv) : (expression' option * type_value) result =
          if k = m then (
            let%bind _ =
              trace (simple_error "constructor parameter doesn't have expected type (shouldn't happen here)")
              @@ AST.assert_type_value_eq (tv, param.type_annotation) in
            ok (Some (param'_expr), param'_tv)
          ) else (
            let%bind tv = translate_type tv in
            ok (None, tv)
          ) in
        let node a b : (expression' option * type_value) result =
          let%bind a = a in
          let%bind b = b in
          match (a, b) with
          | (None, a), (None, b) -> ok (None, T_or (a, b))
          | (Some _, _), (Some _, _) -> simple_fail "several identical constructors in the same variant (shouldn't happen here)"
          | (Some v, a), (None, b) -> ok (Some (E_constant ("LEFT", [v, a, env])), T_or (a, b))
          | (None, a), (Some v, b) -> ok (Some (E_constant ("RIGHT", [v, b, env])), T_or (a, b))
        in
        let%bind (ae_opt, tv) = Append_tree.fold_ne leaf node node_tv in
        let%bind ae =
          trace_option (simple_error "constructor doesn't exist in claimed type (shouldn't happen here)")
            ae_opt in
        ok (ae, tv, env) in
      ok ae'
  | E_tuple lst ->
      let node = Append_tree.of_list lst in
      let aux (a:expression result) (b:expression result) : expression result =
        let%bind (_, a_ty, _) as a = a in
        let%bind (_, b_ty, _) as b = b in
        ok (E_constant ("PAIR", [a; b]), T_pair(a_ty, b_ty), env)
      in
      Append_tree.fold_ne (translate_annotated_expression env) aux node
  | E_tuple_accessor (tpl, ind) ->
      let%bind tpl' = translate_annotated_expression env tpl in
      let%bind tpl_tv = get_t_tuple tpl.type_annotation in
      let node_tv = Append_tree.of_list @@ List.mapi (fun i a -> (i, a)) tpl_tv in
      let leaf (i, _) : expression result =
        if i = ind then (
          ok tpl'
        ) else (
          simple_fail "bad leaf"
        ) in
      let node a b : expression result =
        match%bind bind_lr (a, b) with
        | `Left ((_, t, env) as ex) -> (
            let%bind (a, _) = get_t_pair t in
            ok (E_constant ("CAR", [ex]), a, env)
          )
        | `Right ((_, t, env) as ex) -> (
            let%bind (_, b) = get_t_pair t in
            ok (E_constant ("CDR", [ex]), b, env)
          ) in
      let%bind expr =
        trace_strong (simple_error "bad index in tuple (shouldn't happen here)") @@
        Append_tree.fold_ne leaf node node_tv in
      ok expr
  | E_record m ->
      let node = Append_tree.of_list @@ list_of_map m in
      let aux a b : expression result =
        let%bind (_, a_ty, _) as a = a in
        let%bind (_, b_ty, _) as b = b in
        ok (E_constant ("PAIR", [a; b]), T_pair(a_ty, b_ty), env)
      in
      Append_tree.fold_ne (translate_annotated_expression env) aux node
  | E_record_accessor (record, property) ->
      let%bind translation = translate_annotated_expression env record in
      let%bind record_type_map =
        trace (simple_error (Format.asprintf "Accessing field of %a, that has type %a, which isn't a record" AST.PP.annotated_expression record AST.PP.type_value record.type_annotation)) @@
        get_t_record record.type_annotation in
      let node_tv = Append_tree.of_list @@ kv_list_of_map record_type_map in
      let leaf (key, _) : expression result =
        if property = key then (
          ok translation
        ) else (
          simple_fail "bad leaf"
        ) in
      let node (a:expression result) b : expression result =
        match%bind bind_lr (a, b) with
        | `Left ((_, t, env) as ex) -> (
            let%bind (a, _) = get_t_pair t in
            ok (E_constant ("CAR", [ex]), a, env)
          )
        | `Right ((_, t, env) as ex) -> (
            let%bind (_, b) = get_t_pair t in
            ok (E_constant ("CDR", [ex]), b, env)
          ) in
      let%bind expr =
        trace_strong (simple_error "bad key in record (shouldn't happen here)") @@
        Append_tree.fold_ne leaf node node_tv in
      ok expr
  | E_constant (name, lst) ->
      let%bind lst' = bind_list @@ List.map (translate_annotated_expression env) lst in (
        match name, lst with
        | "NONE", [] ->
            let%bind o = Mini_c.Combinators.get_t_option tv in
            ok (E_make_none o, tv, env)
        | _ -> ok (E_constant (name, lst'), tv, env)
      )
  | E_lambda l -> translate_lambda env l tv
  | E_map m ->
      let%bind (src, dst) = Mini_c.Combinators.get_t_map tv in
      let aux : expression result -> (AST.ae * AST.ae) -> expression result = fun prev (k, v) ->
        let%bind prev' = prev in
        let%bind (k', v') =
          let v' = e_a_some v in
          bind_map_pair (translate_annotated_expression env) (k, v') in
        return (E_constant ("UPDATE", [k' ; v' ; prev']), tv)
      in
      let init = return (E_empty_map (src, dst), tv) in
      List.fold_left aux init m
  | E_look_up dsi ->
      let%bind (ds', i') = bind_map_pair f dsi in
      return (E_constant ("GET", [i' ; ds']), tv)
  | E_matching (expr, m) -> (
      let%bind expr' = translate_annotated_expression env expr in
      match m with
      | AST.Match_bool {match_true ; match_false} ->
          let%bind (t, f) = bind_map_pair (translate_annotated_expression env) (match_true, match_false) in
          return (E_Cond (expr', t, f), tv)
      | AST.Match_list _ | AST.Match_option _ | AST.Match_tuple (_, _) ->
          simple_fail "only match bool exprs are translated yet"
    )

and translate_lambda_shallow env l tv =
  let { binder ; input_type ; output_type ; body ; result } : AST.lambda = l in
  (* Shallow capture. Capture the whole environment. Extend it with a new scope. Append it the input. *)
  let%bind input = translate_type input_type in
  let sub_env = Environment.extend env in
  let full_env = Environment.add (binder, input) sub_env in
  let%bind (_, e) as body = translate_block full_env body in
  let%bind result = translate_annotated_expression e.post_environment result in
  let capture_type = Shallow_capture sub_env in
  let input = Environment.to_mini_c_type full_env in
  let%bind output = translate_type output_type in
  let content = {binder;input;output;body;result;capture_type} in
  ok (E_function content, tv, env)

and translate_lambda env l tv =
  let { binder ; input_type ; output_type ; body ; result } : AST.lambda = l in
  (* Try to type it in an empty env, if it succeeds, transpiles it as a quote value, else, as a closure expression. *)
  let%bind init_env =
    let%bind input = translate_type input_type in
    ok Environment.(add (binder, input) empty) in
  match to_option (translate_block init_env body)  with
  | Some ((_, e) as body) -> (
      match to_option (translate_annotated_expression e.post_environment result) with
      | Some result -> (
          let capture_type = No_capture in
          let%bind input = translate_type input_type in
          let%bind output = translate_type output_type in
          let content = {binder;input;output;body;result;capture_type} in
          ok (E_literal (D_function {capture=None;content}), tv, env)
        )
      | _ -> translate_lambda_shallow init_env l tv
    )
  | _ -> translate_lambda_shallow init_env l tv

let translate_declaration env (d:AST.declaration) : toplevel_statement result =
  match d with
  | Declaration_constant {name;annotated_expression} ->
      let%bind ((_, tv, _) as expression) = translate_annotated_expression env annotated_expression in
      let env' = Environment.add (name, tv) env in
      ok @@ ((name, expression), environment_wrap env env')

let translate_program (lst:AST.program) : program result =
  let aux (prev:(toplevel_statement list * Environment.t) result) cur =
    let%bind (tl, env) = prev in
    let%bind ((_, env') as cur') = translate_declaration env cur in
    ok (cur' :: tl, env'.post_environment)
  in
  let%bind (statements, _) = List.fold_left aux (ok ([], Environment.empty)) lst in
  ok statements

let translate_main (l:AST.lambda) (t:AST.type_value) : anon_function result =
  let%bind t' = translate_type t in
  let%bind (expr, _, _) = translate_lambda Environment.empty l t' in
  match expr with
  | E_literal (D_function f) -> ok f
  | _ -> simple_fail "main is not a function"

(* From a non-functional expression [expr], build the functional expression [fun () -> expr] *)
let functionalize (e:AST.annotated_expression) : AST.lambda * AST.type_value =
  let t = e.type_annotation in
  let open! AST in
  {
    binder = "_" ;
    input_type = Combinators.make_t_unit ;
    output_type = t ;
    result = e ;
    body = [I_skip]
  }, Combinators.(make_t_function make_t_unit t)

let translate_entry (lst:AST.program) (name:string) : anon_function result =
  let rec aux acc (lst:AST.program) =
    match lst with
    | [] -> None
    | hd :: tl -> (
        let AST.Declaration_constant an = hd in
        if an.name = name
        then (
          match an.annotated_expression.expression with
          | E_lambda l -> Some (acc, l, an.annotated_expression.type_annotation)
          | _ ->
              let (a, b) = functionalize an.annotated_expression in
              Some (acc, a, b)
        ) else (
          aux ((AST.I_assignment an) :: acc) tl
        )
      )
  in
  let%bind (lst', l, tv) =
    let%bind (lst', l, tv) =
      trace_option (simple_error "no entry-point with given name")
      @@ aux [] lst in
    ok (List.rev lst', l, tv) in
  let l' = {l with body = lst' @ l.body} in
  trace (simple_error "translate entry")
  @@ translate_main l' tv

open Combinators

let rec exp x n =
  if n = 0
  then 1
  else
    let exp' = exp (x * x) (n / 2) in
    let m = if n mod 2 = 0 then 1 else x in
    m * exp'

let exp2 = exp 2

let extract_constructor (v : value) (tree : _ Append_tree.t') : (string * value * AST.type_value) result =
  let open Append_tree in
  let rec aux tv : (string * value * AST.type_value) result=
    match tv with
    | Leaf (k, t), v -> ok (k, v, t)
    | Node {a}, D_left v -> aux (a, v)
    | Node {b}, D_right v -> aux (b, v)
    | _ -> simple_fail "bad constructor path"
  in
  let%bind (s, v, t) = aux (tree, v) in
  ok (s, v, t)

let extract_tuple (v : value) (tree : AST.type_value Append_tree.t') : ((value * AST.type_value) list) result =
  let open Append_tree in
  let rec aux tv : ((value * AST.type_value) list) result =
    match tv with
    | Leaf t, v -> ok @@ [v, t]
    | Node {a;b}, D_pair (va, vb) ->
        let%bind a' = aux (a, va) in
        let%bind b' = aux (b, vb) in
        ok (a' @ b')
    | _ -> simple_fail "bad tuple path"
  in
  aux (tree, v)

let extract_record (v : value) (tree : _ Append_tree.t') : (_ list) result =
  let open Append_tree in
  let rec aux tv : ((string * (value * AST.type_value)) list) result =
    match tv with
    | Leaf (s, t), v -> ok @@ [s, (v, t)]
    | Node {a;b}, D_pair (va, vb) ->
        let%bind a' = aux (a, va) in
        let%bind b' = aux (b, vb) in
        ok (a' @ b')
    | _ -> simple_fail "bad record path"
  in
  aux (tree, v)


let rec untranspile (v : value) (t : AST.type_value) : AST.annotated_expression result =
  let open! AST in
  let return e = ok AST.(annotated_expression e t) in
  match t.type_value with
  | T_constant ("unit", []) ->
      let%bind () = get_unit v in
      return (E_literal Literal_unit)
  | T_constant ("bool", []) ->
      let%bind b = get_bool v in
      return (E_literal (Literal_bool b))
  | T_constant ("int", []) ->
      let%bind n = get_int v in
      return (E_literal (Literal_int n))
  | T_constant ("string", []) ->
      let%bind n = get_string v in
      return (E_literal (Literal_string n))
  | T_constant ("option", [o]) -> (
      match%bind get_option v with
      | None -> ok (e_a_none o)
      | Some s ->
          let%bind s' = untranspile s o in
          ok (e_a_some s')
    )
  | T_constant ("map", [k_ty;v_ty]) -> (
      let%bind lst = get_map v in
      let%bind lst' =
        let aux = fun (k, v) ->
          let%bind k' = untranspile k k_ty in
          let%bind v' = untranspile v v_ty in
          ok (k', v') in
        bind_map_list aux lst in
      return (E_map lst')
    )
  | T_constant _ ->
      simple_fail "unknown type_constant"
  | T_sum m ->
      let lst = kv_list_of_map m in
      let%bind node = match Append_tree.of_list lst with
        | Empty -> simple_fail "empty sum type"
        | Full t -> ok t
      in
      let%bind (name, v, tv) = extract_constructor v node in
      let%bind sub = untranspile v tv in
      return (E_constructor (name, sub))
  | T_tuple lst ->
      let%bind node = match Append_tree.of_list lst with
        | Empty -> simple_fail "empty tuple"
        | Full t -> ok t in
      let%bind tpl = extract_tuple v node in
      let%bind tpl' = bind_list
        @@ List.map (fun (x, y) -> untranspile x y) tpl in
      return (E_tuple tpl')
  | T_record m ->
      let lst = kv_list_of_map m in
      let%bind node = match Append_tree.of_list lst with
        | Empty -> simple_fail "empty record"
        | Full t -> ok t in
      let%bind lst = extract_record v node in
      let%bind lst = bind_list
        @@ List.map (fun (x, (y, z)) -> let%bind yz = untranspile y z in ok (x, yz)) lst in
      let m' = map_of_kv_list lst in
      return (E_record m')
  | T_function _ -> simple_fail "no untranspilation for functions yet"
