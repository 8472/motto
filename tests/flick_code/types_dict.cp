type bla : dictionary [integer] <integer * integer>

type bla : dictionary [string] record
  key : string
  value : string

type some_type : <string * <integer * string>>

type d : dictionary [type some_type] type some_type


process P : (type T1/type T2 c)
  global d : dictionary [ipv4_address] <string * string> := empty_dictionary
  <>
