(*
   Interactive runtime for Flick programs.
   Nik Sultana, Cambridge University Computer Lab, July 2015
*)

open State
open Crisp_syntax

exception Runtime_inspect_exc of string

type inspect_instruction =
    (*declare and define variable, and initialise*)
  | Declare_value of string * string
    (*set - variable value*)
  | Set of string * string
    (*channel - declare and define channel (in the symbol table and runtime context)*)
  | Declare_channel of string
    (*close_channel - break a channel (the connected processes should react to this)*)
  | Close_channel of string
    (*queue channel value*)
  | Q_channel of string * string
    (*dequeue channel value*)
  | Deq_channel of string
    (*load - Flick program from file*)
  | Load of string
    (*Evaluate a Flick expression.
      If a process is called, then it runs for a single iteration.*)
  | Eval of string
    (*execute some meta-instruction, e.g., to show the whole runtime context,
      or specific parts of it, or the symbol_table*)
  | MI of meta_instruction

(*Evaluate a single inspect-instruction*)
let eval (st : state) (ctxt : Runtime_data.runtime_ctxt) (i : inspect_instruction) : (state * Runtime_data.runtime_ctxt) =
  match i with
  | Declare_value (v, e_s) ->
    let e =
      match Crisp_parse.parse_string ("(| " ^ e_s ^ "|)") with
      | Expression e -> e
      | _ ->
        raise (Runtime_inspect_exc ("Could not parse into an expression: " ^ e_s)) in
    let ty, st' = Type_infer.ty_of_expr st e in
    (*Remove binding of "v" if it exists*)
    let st'' =
      match lookup_term_data (Term Value) st'.term_symbols v with
      | None -> st'
      | Some (_, md) ->
        begin
        print_endline ("Warning: replacing earlier entry for " ^ v ^ " from symbol table");
        let _ =
          match md.source_type with
          | None ->
            raise (Runtime_inspect_exc ("Found entry in symbol table, but no specific type for " ^ v))
          | Some ty' ->
            if ty = ty' then ()
            else
              let ty_s = type_value_to_string true false min_indentation ty in
              let ty'_s = type_value_to_string true false min_indentation ty' in
              print_endline ("(Moreover type of symbol " ^ v ^ " is being changed from " ^ ty'_s ^ " to " ^ ty_s ^ ")") in
        { st' with term_symbols = List.filter (fun (v', _, _) -> v <> v') st'.term_symbols }
        end in
    let _, st''' = Naasty_aux.extend_scope_unsafe (Term Value) st'' v in
    let value = Eval.evaluate_value ctxt e in
    (*Just push new value of "v", without checking if it exists*)
    let ctxt' =
      if List.mem_assoc v ctxt.Runtime_data.value_table then
        begin
        print_endline ("Warning: replacing earlier entry for " ^ v ^ " from runtime state");
        { ctxt with Runtime_data.value_table = List.filter (fun (v', _) -> v <> v') ctxt.Runtime_data.value_table }
        end
      else ctxt in
    let ctxt'' =
      { ctxt' with Runtime_data.value_table = (v, value) :: ctxt'.Runtime_data.value_table } in
    (st''', ctxt'')
  | Set (v, e_s) ->
    let e =
      match Crisp_parse.parse_string ("(| " ^ e_s ^ "|)") with
      | Expression e -> e
      | _ ->
        raise (Runtime_inspect_exc ("Could not parse into an expression: " ^ e_s)) in
    let ty, st' = Type_infer.ty_of_expr st e in
    (*Ensure that binding of "v" exists*)
    let _ =
      match lookup_term_data (Term Value) st'.term_symbols v with
      | None ->
        raise (Runtime_inspect_exc ("Could not find entry in symbol table for " ^ v))
      | Some (_, md) ->
        begin
        match md.source_type with
        | None ->
          raise (Runtime_inspect_exc ("Found entry in symbol table, but no specific type for " ^ v))
        | Some ty' ->
          if ty = ty' then ()
          else
            let ty_s = type_value_to_string true false min_indentation ty in
            let ty'_s = type_value_to_string true false min_indentation ty' in
            raise (Runtime_inspect_exc ("Entry in symbol table for " ^ v ^ " is typed " ^ ty'_s ^ " but type of " ^ e_s ^ " is " ^ ty_s))
        end in
    let value = Eval.evaluate_value ctxt e in
    (*Just push new value of "v", and removing earlier value*)
    let ctxt' =
      if List.mem_assoc v ctxt.Runtime_data.value_table then
        { ctxt with Runtime_data.value_table = List.filter (fun (v', _) -> v <> v') ctxt.Runtime_data.value_table }
      else
        raise (Runtime_inspect_exc ("Symbol " ^ v ^ " has been declared previously, but not defined")) in
    let ctxt'' =
      { ctxt' with Runtime_data.value_table = (v, value) :: ctxt'.Runtime_data.value_table } in
    (st, ctxt'')
(*FIXME currently unsupported
  | Declare_channel v ->
  | Close_channel v ->
  | Q_channel (v, e_s) ->
  | Deq_channel v ->
  | Load file_path ->
  | Eval e_s ->
  | MI mi ->
*)

(*Evaluate a list of inspect-instructions*)
let evals (st : state) (ctxt : Runtime_data.runtime_ctxt) (is : inspect_instruction list) : (state * Runtime_data.runtime_ctxt) =
  List.fold_right (fun instr (st, ctxt) ->
    eval st ctxt instr) is (st, ctxt)