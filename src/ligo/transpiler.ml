open! Ligo_helpers.Trace
open Mini_c

module AST = Ast_typed

let list_of_map m = List.rev @@ Ligo_helpers.X_map.String.fold (fun _ v prev -> v :: prev) m []
let kv_list_of_map m = List.rev @@ Ligo_helpers.X_map.String.fold (fun k v prev -> (k, v) :: prev) m []

let rec translate_type (t:AST.type_value) : type_value result =
  match t with
  | Type_constant ("bool", []) -> ok (`Base Bool)
  | Type_constant ("int", []) -> ok (`Base Int)
  | Type_constant ("string", []) -> ok (`Base String)
  | Type_sum m ->
      let node = Append_tree.of_list @@ list_of_map m in
      let aux a b : type_value result =
        let%bind a = a in
        let%bind b = b in
        ok (`Or (a, b))
      in
      Append_tree.fold_ne translate_type aux node
  | Type_record m ->
      let node = Append_tree.of_list @@ list_of_map m in
      let aux a b : type_value result =
        let%bind a = a in
        let%bind b = b in
        ok (`Pair (a, b))
      in
      Append_tree.fold_ne translate_type aux node
  | Type_tuple lst ->
      let node = Append_tree.of_list lst in
      let aux a b : type_value result =
        let%bind a = a in
        let%bind b = b in
        ok (`Pair (a, b))
      in
      Append_tree.fold_ne translate_type aux node
  | _ -> simple_fail "todo"

let rec translate_block env (b:AST.block) : block result =
  let env' = Environment.extend env in
  let%bind instructions = bind_list @@ List.map (translate_instruction env) b in
  ok (instructions, env')

and translate_instruction (env:Environment.t) (i:AST.instruction) : statement result =
  match i with
  | Assignment {name;annotated_expression} ->
      let%bind expression = translate_annotated_expression env annotated_expression in
      ok @@ (Assignment (name, expression), env)
  | Matching (expr, Match_bool {match_true ; match_false}) ->
      let%bind expr' = translate_annotated_expression env expr in
      let%bind true_branch = translate_block env match_true in
      let%bind false_branch = translate_block env match_false in
      ok @@ (Cond (expr', true_branch, false_branch), env)
  | Loop (expr, body) ->
      let%bind expr' = translate_annotated_expression env expr in
      let%bind body' = translate_block env body in
      ok @@ (While (expr', body'), env)
  | _ -> simple_fail "todo"

and translate_annotated_expression (env:Environment.t) (ae:AST.annotated_expression) : expression result =
  let%bind tv = translate_type ae.type_annotation in
  match ae.expression with
  | Literal (Bool b) -> ok (Literal (`Bool b), tv, env)
  | Literal (Int n) -> ok (Literal (`Int n), tv, env)
  | Literal (Nat n) -> ok (Literal (`Nat n), tv, env)
  | Literal (Bytes s) -> ok (Literal (`Bytes s), tv, env)
  | Literal (String s) -> ok (Literal (`String s), tv, env)
  | Literal Unit -> ok (Literal `Unit, tv, env)
  | Variable name -> ok (Var name, tv, env)
  | Application (a, b) ->
      let%bind a = translate_annotated_expression env a in
      let%bind b = translate_annotated_expression env b in
      ok (Apply (a, b), tv, env)
  | Constructor (m, param) ->
      let%bind (param'_expr, param'_tv, _) = translate_annotated_expression env ae in
      let%bind map_tv = AST.get_t_sum ae.type_annotation in
      let node_tv = Append_tree.of_list @@ kv_list_of_map map_tv in
      let%bind ae' =
        let leaf (k, tv) : (expression' option * type_value) result =
          if k = m then (
            let%bind _ =
              trace (simple_error "constructor parameter doesn't have expected type (shouldn't happen here)")
              @@ AST.type_value_eq (tv, param.type_annotation) in
            ok (Some (param'_expr), param'_tv)
          ) else (
            let%bind tv = translate_type tv in
            ok (None, tv)
          ) in
        let node a b : (expression' option * type_value) result =
          let%bind a = a in
          let%bind b = b in
          match (a, b) with
          | (None, a), (None, b) -> ok (None, `Or (a, b))
          | (Some _, _), (Some _, _) -> simple_fail "several identical constructors in the same variant (shouldn't happen here)"
          | (Some v, a), (None, b) -> ok (Some (Predicate ("LEFT", [v, a, env])), `Or (a, b))
          | (None, a), (Some v, b) -> ok (Some (Predicate ("RIGHT", [v, b, env])), `Or (a, b))
        in
        let%bind (ae_opt, tv) = Append_tree.fold_ne leaf node node_tv in
        let%bind ae =
          trace_option (simple_error "constructor doesn't exist in claimed type (shouldn't happen here)")
            ae_opt in
        ok (ae, tv, env) in
      ok ae'
  | Tuple lst ->
      let node = Append_tree.of_list lst in
      let aux (a:expression result) (b:expression result) : expression result =
        let%bind (_, a_ty, _) as a = a in
        let%bind (_, b_ty, _) as b = b in
        ok (Predicate ("PAIR", [a; b]), `Pair(a_ty, b_ty), env)
      in
      Append_tree.fold_ne (translate_annotated_expression env) aux node
  | Tuple_accessor (tpl, ind) ->
      let%bind (tpl'_expr, _, _) = translate_annotated_expression env tpl in
      let%bind tpl_tv = AST.get_t_tuple ae.type_annotation in
      let node_tv = Append_tree.of_list @@ List.mapi (fun i a -> (a, i)) tpl_tv in
      let%bind ae' =
        let leaf (tv, i) : (expression' option * type_value) result =
          let%bind tv = translate_type tv in
          if i = ind then (
            ok (Some (tpl'_expr), tv)
          ) else (
            ok (None, tv)
          ) in
        let node a b : (expression' option * type_value) result =
          let%bind a = a in
          let%bind b = b in
          match (a, b) with
          | (None, a), (None, b) -> ok (None, `Pair (a, b))
          | (Some _, _), (Some _, _) -> simple_fail "several identical indexes in the same tuple (shouldn't happen here)"
          | (Some v, a), (None, b) -> ok (Some (Predicate ("CAR", [v, a, env])), `Pair (a, b))
          | (None, a), (Some v, b) -> ok (Some (Predicate ("CDR", [v, b, env])), `Pair (a, b))
        in
        let%bind (ae_opt, tv) = Append_tree.fold_ne leaf node node_tv in
        let%bind ae = trace_option (simple_error "bad index in tuple (shouldn't happen here)")
            ae_opt in
        ok (ae, tv, env) in
      ok ae'
  | Record m ->
      let node = Append_tree.of_list @@ list_of_map m in
      let aux a b : expression result =
        let%bind (_, a_ty, _) as a = a in
        let%bind (_, b_ty, _) as b = b in
        ok (Predicate ("PAIR", [a; b]), `Pair(a_ty, b_ty), env)
      in
      Append_tree.fold_ne (translate_annotated_expression env) aux node
  | Record_accessor (r, key) ->
      let%bind (r'_expr, _, _) = translate_annotated_expression env r in
      let%bind r_tv = AST.get_t_record ae.type_annotation in
      let node_tv = Append_tree.of_list @@ kv_list_of_map r_tv in
      let%bind ae' =
        let leaf (key', tv) : (expression' option * type_value) result =
          let%bind tv = translate_type tv in
          if key = key' then (
            ok (Some (r'_expr), tv)
          ) else (
            ok (None, tv)
          ) in
        let node a b : (expression' option * type_value) result =
          let%bind a = a in
          let%bind b = b in
          match (a, b) with
          | (None, a), (None, b) -> ok (None, `Pair (a, b))
          | (Some _, _), (Some _, _) -> simple_fail "several identical keys in the same record (shouldn't happen here)"
          | (Some v, a), (None, b) -> ok (Some (Predicate ("CAR", [v, a, env])), `Pair (a, b))
          | (None, a), (Some v, b) -> ok (Some (Predicate ("CDR", [v, b, env])), `Pair (a, b))
        in
        let%bind (ae_opt, tv) = Append_tree.fold_ne leaf node node_tv in
        let%bind ae = trace_option (simple_error "bad key in record (shouldn't happen here)")
            ae_opt in
        ok (ae, tv, env) in
      ok ae'
  | Constant (name, lst) ->
      let%bind lst' = bind_list @@ List.map (translate_annotated_expression env) lst in
      ok (Predicate (name, lst'), tv, env)
  | Lambda { binder ; input_type ; output_type ; body ; result } ->
      (* Try to type it in an empty env, if it succeeds, transpiles it as a quote value, else, as a closure expression. *)
      let%bind empty_env =
        let%bind input = translate_type input_type in
        ok Environment.(add (binder, input) empty) in
      match to_option (translate_block empty_env body), to_option (translate_annotated_expression empty_env result) with
      | Some body, Some result ->
          let capture_type = No_capture in
          let%bind input = translate_type input_type in
          let%bind output = translate_type output_type in
          let content = {binder;input;output;body;result;capture_type} in
          ok (Literal (`Function {capture=None;content}), tv, env)
      | _ ->
          (* Shallow capture. Capture the whole environment. Extend it with a new scope. Append it the input. *)
          let%bind input = translate_type input_type in
          let sub_env = Environment.extend env in
          let full_env = Environment.add (binder, input) sub_env in
          let%bind (_, post_env) as body = translate_block full_env body in
          let%bind result = translate_annotated_expression post_env result in
          let capture_type = Shallow_capture sub_env in
          let input = Environment.to_mini_c_type full_env in
          let%bind output = translate_type output_type in
          let content = {binder;input;output;body;result;capture_type} in
          ok (Function_expression content, tv, env)

let translate_declaration env (d:AST.declaration) : toplevel_statement result =
  match d with
  | Constant_declaration {name;annotated_expression} ->
      let%bind ((_, tv, _) as expression) = translate_annotated_expression env annotated_expression in
      let env' = Environment.add (name, tv) env in
      ok @@ ((name, expression), env')

let translate_program (lst:AST.program) : program result =
  let aux (prev:(toplevel_statement list * Environment.t) result) cur =
    let%bind (tl, env) = prev in
    let%bind ((_, env') as cur') = translate_declaration env cur in
    ok (cur' :: tl, env')
  in
  let%bind (statements, _) = List.fold_left aux (ok ([], Environment.empty)) lst in
  ok statements
