[@deriving (eq, ord, yojson)]
type t =
  Tezos.Ticket_id.t = {
    ticketer: Tezos.Address.t,
    data: bytes,
  };
