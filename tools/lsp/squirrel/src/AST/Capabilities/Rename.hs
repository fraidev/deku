-- | Rename request implementation.
module AST.Capabilities.Rename
  ( RenameDeclarationResult (..)
  , renameDeclarationAt
  ) where

import Data.Text (Text)
import qualified Language.Haskell.LSP.Types as J

import AST.Capabilities.Find (CanSearch, findScopedDecl)
import AST.Scope (ScopedDecl (ScopedDecl, _sdRefs))
import AST.Skeleton (LIGO)
import Range (Range, toLspRange)


-- | Result of trying to rename declaration.
data RenameDeclarationResult = Ok [J.TextEdit] | NotFound
  deriving (Eq, Show)


-- | Rename the declaration at the given position.
-- The position is given as a range, becuase that is how we do it, haha :/.
renameDeclarationAt
  :: CanSearch xs
  => Range -> LIGO xs -> Text -> RenameDeclarationResult
renameDeclarationAt pos tree newName =
    case findScopedDecl pos tree of
      Nothing -> NotFound
      Just ScopedDecl{_sdRefs} -> Ok $
        -- XXX: _sdRefs includes the declaration itself too,
        -- so we do not add _sdOrigin.
        map (\r -> J.TextEdit (toLspRange r) newName) _sdRefs
