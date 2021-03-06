(*
  Simple test framework for the Crisp parser
  Nik Sultana, Cambridge University Computer Lab, January 2015
  Jonny Shipton, Cambridge University Computer Lab, June 2016

  Use of this source code is governed by the Apache 2.0 license; see LICENSE
*)

open Lexing
open Crisp_syntax
open Crisp_parser
open Crisp_parse
open General

let is_bad_test filename =
  let bad = ".bad." in
  let bad_len = String.length bad in
  let len = String.length filename in
  let rec contains_bad_from start =
    let dotIndex = String.index_from filename start '.' in
    let startsWithBad = (len - dotIndex >= bad_len) &&
      (bad = String.sub filename dotIndex bad_len) in
    startsWithBad || contains_bad_from (dotIndex + 1) in
  try contains_bad_from 0 with Not_found -> false

let loop filename () =
  print_endline "Starting source program";
  let contents = parse_file filename in
  contents
  |> Crisp_syntax.source_file_contents_to_string
  |> print_endline;
  print_endline "Finished source program";
  if (contents <> Empty && is_bad_test filename) then
    Printf.eprintf "%s test file %s didn't fail\n" Terminal.warning filename
  else if (contents = Empty && not (is_bad_test filename)) then
    Printf.eprintf "%s test file %s failed\n" Terminal.warning filename
(*FIXME this next block is very rudimentary
  print_endline "Starting translated program";
  result
  |> Translation.naasty_of_flick_program
  |> fst (*NOTE discarding state*)
  |> Naasty_aux.string_of_naasty_program Naasty_aux.prog_indentation
  |> print_endline;
  print_endline "Finished translated program"
*)
;;

(*
let loop filename () =
  let inx = In_channel.create filename in
  let lexbuf = Lexing.from_channel inx in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
  let result = Crisp_parser.program Crisp_lexer.main lexbuf in
  In_channel.close inx;
  result
  ;;
*)

let lex_looper filename () =
  let inx = open_in filename in
  let lexbuf = Lexing.from_channel inx in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
  let results =
    (*NOTE will return what was lexed until error or end*)
    let rec contents acc =
      match Crisp_parse.lex_step_with_error ~silent:true lexbuf with
      | None -> List.rev acc (*error - return what we have so far*)
      | Some (Crisp_parser.EOF as t) -> List.rev (t :: acc)
      | Some t -> contents (t :: acc)
    in contents [] in
  begin
    close_in inx;
    results
  end

let string_of_token = function
  (*Punctuation*)
  | COLON -> "COLON"
  | LEFT_R_BRACKET -> "LEFT_R_BRACKET"
  | RIGHT_R_BRACKET -> "RIGHT_R_BRACKET"
  | LEFT_S_BRACKET -> "LEFT_S_BRACKET"
  | RIGHT_S_BRACKET -> "RIGHT_S_BRACKET"
  | LEFT_C_BRACKET -> "LEFT_C_BRACKET"
  | RIGHT_C_BRACKET -> "RIGHT_C_BRACKET"
  | DASH -> "DASH"
  | EOF -> "EOF"
  | COMMA -> "COMMA"
  | NL -> "NL"

  | UNDENTN (x, _) -> "UNDENTN(" ^ string_of_int x ^ ")"
  | INDENT -> "INDENT"
  | UNDENT -> "UNDENT"

  (*Reserved words*)
  | TYPE -> "TYPE"
  | TYPE_INTEGER -> "TYPE_INTEGER"
  | TYPE_BOOLEAN -> "TYPE_BOOLEAN"
  | TYPE_STRING -> "TYPE_STRING"
  | TYPE_RECORD -> "TYPE_RECORD"
  | TYPE_VARIANT -> "TYPE_VARIANT"
  | TYPE_LIST -> "TYPE_LIST"
(*
  (*Names*)
  | UPPER_ALPHA x -> "UPPER_ALPHA(" ^ x ^ ")"
  | LOWER_ALPHA x -> "LOWER_ALPHA(" ^ x ^ ")"
  | NAT_NUM x -> "NAT_NUM(" ^ x ^ ")"
  | VARIABLE x -> "VARIABLE(" ^ x ^ ")"
*)
  | IDENTIFIER x -> "IDENTIFIER(" ^ x ^ ")"

  | PROC -> "PROC"
  | SLASH -> "SLASH"
  | ARR_RIGHT -> "ARR_RIGHT"

  | TYPE_IPv4ADDRESS -> "TYPE_IPv4ADDRESS"
  | TRUE -> "TRUE"
  | PLUS -> "PLUS"
  | PERIOD -> "PERIOD"
  | OR -> "OR"
  | NOT -> "NOT"
  | LT -> "LT"
  | LOCAL -> "LOCAL"
  | LET -> "LET"
  | IPv4 _ -> "IPv4 _"
  | INTEGER i -> "INTEGER " ^ string_of_int i
  | IN -> "IN"
  | IF -> "IF"
  | GT -> "GT"
  | GLOBAL -> "GLOBAL"
  | FUN -> "FUN"
  | FALSE -> "FALSE"
  | EQUALS -> "EQUALS"
  | ELSE -> "ELSE"
  | ASSIGN -> "ASSIGN"
  | AR_RIGHT -> "AR_RIGHT"
  | AND -> "AND"

  | SEMICOLON -> "SEMICOLON"
  | EXCEPT -> "EXCEPT"

  | ASTERISK -> "ASTERISK"
  | MOD -> "MOD"
  | ABS -> "ABS"

  | ADDRESS_TO_INT -> "ADDRESS_TO_INT"
  | INT_TO_ADDRESS -> "INT_TO_ADDRESS"

  | COLONCOLON -> "COLONCOLON"
  | LEFT_RIGHT_S_BRACKETS -> "LEFT_RIGHT_S_BRACKETS"
  | AT -> "AT"
  | TYPE_TUPLE -> "TYPE_TUPLE"
  | WITH -> "WITH"
  | SWITCH -> "SWITCH"

  | PERIODPERIOD -> "PERIODPERIOD"
  | FOR -> "FOR"
  | INITIALLY -> "INITIALLY"
  | MAP -> "MAP"
  | UNORDERED -> "UNORDERED"
  | ARG_NAMING -> "ARG_NAMING"
  | ARR_LEFT -> "ARR_LEFT"
  | ARR_BOTH -> "ARR_BOTH"

  | INCLUDE -> "INCLUDE"
  | STRING s -> "STRING \"" ^ s ^ "\""

  | TYPE_DICTIONARY -> "TYPE_DICTIONARY"
  | TYPE_REF -> "TYPE_REF"

  | UNDERSCORE -> "UNDERSCORE"

  | FAT_BRACKET_OPEN -> "FAT_BRACKET_OPEN"
  | FAT_BRACKET_CLOSE -> "FAT_BRACKET_CLOSE"
  | FAT_TYPE_BRACKET_OPEN -> "FAT_TYPE_BRACKET_OPEN"

  | TYPED -> "TYPED"
  | META_OPEN -> "META_OPEN"
  | META_CLOSE -> "META_CLOSE"

  | BANG -> "BANG"
  | QUESTION -> "QUESTION"
  | QUESTIONQUESTION -> "QUESTIONQUESTION"

  | BAR -> "BAR"
  | CAN -> "CAN"
  | UNSAFE_CAST -> "UNSAFE_CAST"

  | SIZE -> "SIZE"
;;
let get_expanded_filtered_tokens filename () =
  let inx = open_in filename in
  let lexbuf = Lexing.from_channel inx in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
  let lexer = (Crisp_lexer.main
              |> expand_macro_tokens
              |> filter_redundant_newlines) in
  let results =
    (*NOTE will return what was lexed until error or end*)
    let rec contents acc =
      match Crisp_parse.lex_with_error ~silent:true lexer lexbuf with
      | None -> List.rev acc (*error - return what we have so far*)
      | Some (Crisp_parser.EOF as t) -> List.rev (t :: acc)
      | Some t -> contents (t :: acc)
    in contents [] in
  begin
    close_in inx;
    results
  end

let test filepath =
  print_endline ("Testing " ^ filepath);
  Printf.printf "Lexed tokens:\n";
  Printf.printf "%s\n"
    (lex_looper filepath ()
     |> List.map string_of_token
     |> String.concat ", ");
  Printf.printf "Lexed tokens, expanded and filtered:\n";
  Printf.printf "%s\n"
    (get_expanded_filtered_tokens filepath ()
     |> List.map string_of_token
     |> String.concat ", ");
  loop filepath ()
;;

(*Only considers files ending in ".cp"*)
let test_whole_dir testdir =
  let ending = ".cp" in
  let ending_length = String.length ending in
  let endsWithCP filename =
    let filename_length = String.length filename in
    filename_length > ending_length &&
      ending = String.sub filename
                          (filename_length - ending_length)
                          ending_length in
  let filenames = 
    Sys.readdir testdir 
    |> Array.to_list 
    |> List.filter endsWithCP 
    |> List.sort compare
    |> List.map (Filename.concat testdir) in 
  List.iter (fun filename -> test filename) filenames
;;

let run_parser_test directories files =
  begin
  print_endline "*crisp* *crisp*";

  List.iter test_whole_dir (List.rev directories);
  List.iter test (List.rev files);
  end
