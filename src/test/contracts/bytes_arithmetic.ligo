function concat_op (const s : bytes) : bytes is
  begin skip end with bytes_concat(s , ("7070" : bytes))

function slice_op (const s : bytes) : bytes is
  begin skip end with bytes_slice(1n , 2n , s)

function hasherman (const s : bytes) : bytes is
  begin skip end with sha_256(s)