// Test michelson insertion in CameLIGO

let michelson_add (n : nat * nat) : nat =
  [%Michelson ({| UNPAIR;ADD |} : nat * nat -> nat) ] n
