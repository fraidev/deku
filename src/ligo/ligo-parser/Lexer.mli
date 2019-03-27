(* Lexer specification for LIGO, to be processed by [ocamllex].

   The underlying design principles are:

     (1) enforce stylistic constraints at a lexical level, in order to
         early reject potentially misleading or poorly written
         LIGO contracts;

     (2) provide precise error messages with hint as how to fix the
         issue, which is achieved by consulting the lexical
         right-context of lexemes;

     (3) be as independent as possible from the LIGO version, so
         upgrades have as little impact as possible on this
         specification: this is achieved by using the most general
         regular expressions to match the lexing buffer and broadly
         distinguish the syntactic categories, and then delegating a
         finer, protocol-dependent, second analysis to an external
         module making the tokens (hence a functor below);

     (4) support unit testing (lexing of the whole input with debug
         traces);

   The limitation to the protocol independence lies in the errors that
   the external module building the tokens (which is
   protocol-dependent) may have to report. Indeed these errors have to
   be contextualised by the lexer in terms of input source regions, so
   useful error messages can be printed, therefore they are part of
   the signature [TOKEN] that parameterise the functor generated
   here. For instance, if, in a future release of LIGO, new tokens may
   be added, and the recognition of their lexemes may entail new
   errors, the signature [TOKEN] will have to be augmented and the
   lexer specification changed. However, it is more likely that
   instructions or types are added, instead of new kinds of tokens.
*)

type lexeme = string

(* TOKENS *)

(* The signature [TOKEN] exports an abstract type [token], so a lexer
   can be a functor over tokens. This enables to externalise
   version-dependent constraints in any module whose signature matches
   [TOKEN]. Generic functions to construct tokens are required.

   Note the predicate [is_eof], which caracterises the virtual token
   for end-of-file, because it requires special handling. Some of
   those functions may yield errors, which are defined as values of
   the type [int_err] etc. These errors can be better understood by
   reading the ocamllex specification for the lexer ([Lexer.mll]).
*)

module type TOKEN =
  sig
    type token

    (* Errors *)

    type   int_err = Non_canonical_zero
    type ident_err = Reserved_name

    (* Injections *)

    val mk_string : lexeme -> Region.t -> token
    val mk_bytes  : lexeme -> Region.t -> token
    val mk_int    : lexeme -> Region.t -> (token,   int_err) result
    val mk_ident  : lexeme -> Region.t -> (token, ident_err) result
    val mk_constr : lexeme -> Region.t -> token
    val mk_sym    : lexeme -> Region.t -> token
    val eof       : Region.t -> token

    (* Predicates *)

    val is_string : token -> bool
    val is_bytes  : token -> bool
    val is_int    : token -> bool
    val is_ident  : token -> bool
    val is_kwd    : token -> bool
    val is_constr : token -> bool
    val is_sym    : token -> bool
    val is_eof    : token -> bool

    (* Projections *)

    val to_lexeme : token -> lexeme
    val to_string : token -> ?offsets:bool -> [`Byte | `Point] -> string
    val to_region : token -> Region.t
  end

(* The module type for lexers is [S]. It mainly exports the function
   [open_token_stream], which returns

     * a function [read] that extracts tokens from a lexing buffer,
     * together with a lexing buffer [buffer] to read from,
     * a function [close] that closes that buffer,
     * a function [get_pos] that returns the current position, and
     * a function [get_last] that returns the region of the last
       recognised token.

   Note that a module [Token] is exported too, because the signature
   of the exported functions depend on it.

   The call [read ~log] evaluates in a lexer (a.k.a tokeniser or
   scanner) whose type is [Lexing.lexbuf -> token], and suitable for a
   parser generated by Menhir.

   The argument labelled [log] is a logger. It may print a token and
   its left markup to a given channel, at the caller's discretion.
*)

module type S =
  sig
    module Token : TOKEN
    type token = Token.token

    type file_path = string
    type logger = Markup.t list -> token -> unit

    val output_token :
      ?offsets:bool -> [`Byte | `Point] ->
      EvalOpt.command -> out_channel -> logger

    type instance = {
      read     : ?log:logger -> Lexing.lexbuf -> token;
      buffer   : Lexing.lexbuf;
      get_pos  : unit -> Pos.t;
      get_last : unit -> Region.t;
      close    : unit -> unit
    }

    val open_token_stream : file_path option -> instance

    (* Error reporting *)

    exception Error of Error.t Region.reg

    val print_error : ?offsets:bool -> [`Byte | `Point] ->
                      Error.t Region.reg -> unit

    (* Standalone tracer *)

    val trace :
      ?offsets:bool -> [`Byte | `Point] ->
      file_path option -> EvalOpt.command -> unit
  end

(* The functorised interface

   Note that the module parameter [Token] is re-exported as a
   submodule in [S].
*)

module Make (Token: TOKEN) : S with module Token = Token
