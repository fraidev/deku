let main (p, s : bool * unit) =
  let u : unit = assert p
  in ([] : operation list), s

let some (o : unit option) =
  assert_some o
