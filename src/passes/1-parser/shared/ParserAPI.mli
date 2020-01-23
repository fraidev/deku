(* Generic parser API for LIGO *)

module Region = Simple_utils.Region

(* The signature generated by Menhir with additional type definitions
   for [ast] and [expr]. *)

module type PARSER =
  sig
    (* The type of tokens. *)

    type token
    type ast
    type expr

    (* This exception is raised by the monolithic API functions. *)

    exception Error

    (* The monolithic API. *)

    val interactive_expr :
      (Lexing.lexbuf -> token) -> Lexing.lexbuf -> expr
    val contract :
      (Lexing.lexbuf -> token) -> Lexing.lexbuf -> ast

    (* The incremental API. *)

    module MenhirInterpreter :
      sig
        include MenhirLib.IncrementalEngine.INCREMENTAL_ENGINE
                with type token = token
      end

    (* The entry point(s) to the incremental API. *)

    module Incremental :
      sig
        val interactive_expr :
          Lexing.position -> expr MenhirInterpreter.checkpoint
        val contract :
          Lexing.position -> ast MenhirInterpreter.checkpoint
      end
  end

module Make (Lexer: Lexer.S)
            (Parser: PARSER with type token = Lexer.Token.token)
            (ParErr: sig val message : int -> string end) :
  sig
    (* The monolithic API of Menhir *)

    val mono_contract :
      (Lexing.lexbuf -> Lexer.token) -> Lexing.lexbuf -> Parser.ast

    val mono_expr :
      (Lexing.lexbuf -> Lexer.token) -> Lexing.lexbuf -> Parser.expr

    (* Incremental API of Menhir *)

    type message = string
    type valid   = Parser.token
    type invalid = Parser.token
    type error   = message * valid option * invalid

    exception Point of error

    val incr_contract : Lexer.instance -> Parser.ast
    val incr_expr     : Lexer.instance -> Parser.expr

    val format_error : ?offsets:bool -> [`Point | `Byte] -> error -> string
  end