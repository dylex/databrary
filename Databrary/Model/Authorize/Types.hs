{-# LANGUAGE TemplateHaskell #-}
module Databrary.Model.Authorize.Types
  ( Authorization(..)
  , MonadHasAuthorization
  , Authorize(..)
  , MonadHasAuthorize
  ) where

import Control.Has (makeHasRec)
import Databrary.Time
import Databrary.Model.Permission.Types
import Databrary.Model.Party.Types

data Authorization = Authorization
  { authorizeAccess :: !Access
  , authorizeChild :: Party
  , authorizeParent :: Party
  }

makeHasRec ''Authorization ['authorizeAccess]

data Authorize = Authorize
  { authorization :: Authorization
  , authorizeExpires :: Maybe Timestamp
  }

makeHasRec ''Authorize ['authorization]