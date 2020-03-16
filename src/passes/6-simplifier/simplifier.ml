module I = Ast_sugar
module O = Ast_core
open Trace

let rec idle_type_expression : I.type_expression -> O.type_expression result =
  fun te ->
  let return te = ok @@ O.make_t te in
  match te.type_content with
    | I.T_sum sum -> 
      let sum = I.CMap.to_kv_list sum in
      let%bind sum = 
        bind_map_list (fun (k,v) ->
          let%bind v = idle_type_expression v in
          ok @@ (k,v)
        ) sum
      in
      return @@ O.T_sum (O.CMap.of_list sum)
    | I.T_record record -> 
      let record = I.LMap.to_kv_list record in
      let%bind record = 
        bind_map_list (fun (k,v) ->
          let%bind v = idle_type_expression v in
          ok @@ (k,v)
        ) record
      in
      return @@ O.T_record (O.LMap.of_list record)
    | I.T_arrow {type1;type2} ->
      let%bind type1 = idle_type_expression type1 in
      let%bind type2 = idle_type_expression type2 in
      return @@ T_arrow {type1;type2}
    | I.T_variable type_variable -> return @@ T_variable type_variable 
    | I.T_constant type_constant -> return @@ T_constant type_constant
    | I.T_operator type_operator ->
      let%bind type_operator = idle_type_operator type_operator in
      return @@ T_operator type_operator

and idle_type_operator : I.type_operator -> O.type_operator result =
  fun t_o ->
  match t_o with
    | TC_contract c -> 
      let%bind c = idle_type_expression c in
      ok @@ O.TC_contract c
    | TC_option o ->
      let%bind o = idle_type_expression o in
      ok @@ O.TC_option o
    | TC_list l ->
      let%bind l = idle_type_expression l in
      ok @@ O.TC_list l
    | TC_set s ->
      let%bind s = idle_type_expression s in
      ok @@ O.TC_set s
    | TC_map (k,v) ->
      let%bind (k,v) = bind_map_pair idle_type_expression (k,v) in
      ok @@ O.TC_map (k,v)
    | TC_big_map (k,v) ->
      let%bind (k,v) = bind_map_pair idle_type_expression (k,v) in
      ok @@ O.TC_big_map (k,v)
    | TC_arrow (i,o) ->
      let%bind (i,o) = bind_map_pair idle_type_expression (i,o) in
      ok @@ O.TC_arrow (i,o)

let rec simplify_expression : I.expression -> O.expression result =
  fun e ->
  let return expr = ok @@ O.make_expr ~loc:e.location expr in
  match e.expression_content with
    | I.E_literal literal   -> return @@ O.E_literal literal
    | I.E_constant {cons_name;arguments} -> 
      let%bind arguments = bind_map_list simplify_expression arguments in
      return @@ O.E_constant {cons_name;arguments}
    | I.E_variable name     -> return @@ O.E_variable name
    | I.E_application {expr1;expr2} -> 
      let%bind expr1 = simplify_expression expr1 in
      let%bind expr2 = simplify_expression expr2 in
      return @@ O.E_application {expr1; expr2}
    | I.E_lambda lambda ->
      let%bind lambda = simplify_lambda lambda in
      return @@ O.E_lambda lambda
    | I.E_recursive {fun_name;fun_type;lambda} ->
      let%bind fun_type = idle_type_expression fun_type in
      let%bind lambda = simplify_lambda lambda in
      return @@ O.E_recursive {fun_name;fun_type;lambda}
    | I.E_let_in {let_binder;inline;rhs;let_result} ->
      let (binder,ty_opt) = let_binder in
      let%bind ty_opt = bind_map_option idle_type_expression ty_opt in
      let%bind rhs = simplify_expression rhs in
      let%bind let_result = simplify_expression let_result in
      return @@ O.E_let_in {let_binder=(binder,ty_opt);inline;rhs;let_result}
    | I.E_skip -> return @@ O.E_skip
    | I.E_constructor {constructor;element} ->
      let%bind element = simplify_expression element in
      return @@ O.E_constructor {constructor;element}
    | I.E_matching {matchee; cases} ->
      let%bind matchee = simplify_expression matchee in
      let%bind cases   = simplify_matching cases in
      return @@ O.E_matching {matchee;cases}
    | I.E_record record ->
      let record = I.LMap.to_kv_list record in
      let%bind record = 
        bind_map_list (fun (k,v) ->
          let%bind v =simplify_expression v in
          ok @@ (k,v)
        ) record
      in
      return @@ O.E_record (O.LMap.of_list record)
    | I.E_record_accessor {expr;label} ->
      let%bind expr = simplify_expression expr in
      return @@ O.E_record_accessor {expr;label}
    | I.E_record_update {record;path;update} ->
      let%bind record = simplify_expression record in
      let%bind update = simplify_expression update in
      return @@ O.E_record_update {record;path;update}
    | I.E_map map ->
      let%bind map = bind_map_list (
        bind_map_pair simplify_expression
      ) map
      in
      return @@ O.E_map map
    | I.E_big_map big_map ->
      let%bind big_map = bind_map_list (
        bind_map_pair simplify_expression
      ) big_map
      in
      return @@ O.E_big_map big_map
    | I.E_list lst ->
      let%bind lst = bind_map_list simplify_expression lst in
      return @@ O.E_list lst
    | I.E_set set ->
      let%bind set = bind_map_list simplify_expression set in
      return @@ O.E_set set 
    | I.E_look_up look_up ->
      let%bind look_up = bind_map_pair simplify_expression look_up in
      return @@ O.E_look_up look_up
    | I.E_ascription {anno_expr; type_annotation} ->
      let%bind anno_expr = simplify_expression anno_expr in
      let%bind type_annotation = idle_type_expression type_annotation in
      return @@ O.E_ascription {anno_expr; type_annotation}

and simplify_lambda : I.lambda -> O.lambda result =
  fun {binder;input_type;output_type;result}->
    let%bind input_type = bind_map_option idle_type_expression input_type in
    let%bind output_type = bind_map_option idle_type_expression output_type in
    let%bind result = simplify_expression result in
    ok @@ O.{binder;input_type;output_type;result}
and simplify_matching : I.matching_expr -> O.matching_expr result =
  fun m -> 
  match m with 
    | I.Match_bool {match_true;match_false} ->
      let%bind match_true = simplify_expression match_true in
      let%bind match_false = simplify_expression match_false in
      ok @@ O.Match_bool {match_true;match_false}
    | I.Match_list {match_nil;match_cons} ->
      let%bind match_nil = simplify_expression match_nil in
      let (hd,tl,expr,tv) = match_cons in
      let%bind expr = simplify_expression expr in
      ok @@ O.Match_list {match_nil; match_cons=(hd,tl,expr,tv)}
    | I.Match_option {match_none;match_some} ->
      let%bind match_none = simplify_expression match_none in
      let (n,expr,tv) = match_some in
      let%bind expr = simplify_expression expr in
      ok @@ O.Match_option {match_none; match_some=(n,expr,tv)}
    | I.Match_tuple ((lst,expr), tv) ->
      let%bind expr = simplify_expression expr in
      ok @@ O.Match_tuple ((lst,expr), tv)
    | I.Match_variant (lst,tv) ->
      let%bind lst = bind_map_list (
        fun ((c,n),expr) ->
          let%bind expr = simplify_expression expr in
          ok @@ ((c,n),expr)
      ) lst 
      in
      ok @@ O.Match_variant (lst,tv)
 
let simplify_declaration : I.declaration Location.wrap -> _ =
  fun {wrap_content=declaration;location} ->
  let return decl = ok @@ Location.wrap ~loc:location decl in
  match declaration with 
  | I.Declaration_constant (n, te_opt, inline, expr) ->
    let%bind expr = simplify_expression expr in
    let%bind te_opt = bind_map_option idle_type_expression te_opt in
    return @@ O.Declaration_constant (n, te_opt, inline, expr)
  | I.Declaration_type (n, te) ->
    let%bind te = idle_type_expression te in
    return @@ O.Declaration_type (n,te)

let simplify_program : I.program -> O.program result =
  fun p ->
  bind_map_list simplify_declaration p
