open Format
open Sgtp
open Syntax

let debug = ref false

let empty_formatter = make_formatter (fun _ _ _ -> ()) (fun _ -> ())

let rec read_eval_print lexbuf env tyenv =
  (* Used in all modes *)
  let print f = fprintf std_formatter f in
  (* Used in debug mode *)
  let print_debug f = (if !debug then print else fprintf empty_formatter) f in
  print "# @?";
  flush stdout;
  begin try
      (* Parsing *)
      let e = Parser.toplevel Lexer.main lexbuf in

      (* Type inference *)
      let u, s, tau = Typing.GTLC.type_of_exp tyenv e in
      let e = Typing.GTLC.subst_exp_substitutions e s in
      let e, u = Typing.GTLC.subst_tyvars_gtyparams tau e u in
      let e, u = Typing.GTLC.subst_tyvars_styparams e u in
      print_debug "GTLC e: %a\n" Pp.GTLC.pp_exp e;
      print_debug "GTLC U: %a\n" Pp.pp_ty u;

      (* Translation *)
      let f, u' = Typing.GTLC.translate tyenv e in
      print_debug "CC e: %a\n" Pp.CC.pp_exp f;
      print_debug "CC U: %a\n" Pp.pp_ty u';
      assert (u = u');
      let u'' = Typing.CC.type_of_exp tyenv f in
      assert (u = u'');

      (* Evaluation *)
      let v, s = Eval.eval f ~debug:!debug in
      print_debug "CC v: %a\n" Pp.CC.pp_exp v;
      print_debug "GTP Subst: %a\n" Eval.pp_substitutions s;
      print "- : %a = %a\n" Pp.pp_ty (Eval.subst_gtp_in_type s u) Pp.CC.pp_value v
    with
    | Failure message ->
      print "Failure: %s\n" message;
      Lexing.flush_input lexbuf
    | Parser.Error -> (* Menhir *)
      let token = Lexing.lexeme lexbuf in
      print "Parser.Error: unexpected token %s\n" token;
      Lexing.flush_input lexbuf
    | Typing.Type_error message ->
      print "Type_error: %s\n" message
    | Eval.Blame r ->
      print "Blame: %a\n"
        Utils.Error.pp_range r
  end;
  read_eval_print lexbuf env tyenv

let () =
  let options = Arg.align [
      ("-d", Arg.Unit (fun () -> debug := true), " Enable debug mode");
    ] in
  Arg.parse options (fun _ -> ()) "help";
  let lexbuf = Lexing.from_channel stdin in
  let env = Environment.empty in
  let tyenv = Environment.empty in
  read_eval_print lexbuf env tyenv
