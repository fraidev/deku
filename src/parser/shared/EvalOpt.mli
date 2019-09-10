(* Parsing the command-line options of PascaLIGO *)

(* The type [command] denotes some possible behaviours of the
   compiler. The constructors are

    * [Quiet], then no output from the lexer and parser should be
      expected, safe error messages: this is the default value;
    * [Copy], then lexemes of tokens and markup will be printed to
      standard output, with the expectation of a perfect match with
      the input file;
    * [Units], then the tokens and markup will be printed to standard
      output, that is, the abstract representation of the concrete
      lexical syntax;
    * [Tokens], then the tokens only will be printed.
*)

type command = Quiet | Copy | Units | Tokens

(* The type [options] gathers the command-line options.

     If the field [input] is [Some src], the name of the PascaLIGO
   source file, with the extension ".ligo", is [src]. If [input] is
   [Some "-"] or [None], the source file is read from standard input.

     The field [libs] is the paths where to find PascaLIGO files for
   inclusion (#include).

     The field [verbose] is a set of stages of the compiler chain,
   about which more information may be displayed.

     If the field [offsets] is [true], then the user requested that
   messages about source positions and regions be expressed in terms
   of horizontal offsets.

     If the value [mode] is [`Byte], then the unit in which source
   positions and regions are expressed in messages is the byte. If
   [`Point], the unit is unicode points.

*)

type options = {
  input   : string option;
  libs    : string list;
  verbose : Utils.String.Set.t;
  offsets : bool;
  mode    : [`Byte | `Point];
  cmd     : command
}

(* Parsing the command-line options on stdin *)

val read : unit -> options