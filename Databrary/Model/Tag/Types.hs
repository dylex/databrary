{-# LANGUAGE OverloadedStrings, TemplateHaskell, TypeFamilies, DataKinds, GeneralizedNewtypeDeriving, DeriveDataTypeable #-}
module Databrary.Model.Tag.Types
  ( TagName(..)
  , validateTag
  , Tag(..)
  , MonadHasTag
  , TagUse(..)
  , MonadHasTagUse
  , TagCoverage(..)
  , MonadHasTagCoverage
  , TagWeight(..)
  , MonadHasTagWeight
  ) where

import Control.Monad ((<=<))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Typeable (Typeable)
import Database.PostgreSQL.Typed.Types (PGParameter(..), PGColumn(..))
import qualified Text.Regex.Posix as Regex

import Databrary.Ops
import Databrary.Has (makeHasRec)
import qualified Databrary.JSON as JSON
import Databrary.HTTP.Path.Types
import Databrary.Model.Kind
import Databrary.Model.Id.Types
import Databrary.Model.Party.Types
import Databrary.Model.Container.Types
import Databrary.Model.Segment
import Databrary.Model.Slot.Types

newtype TagName = TagName BS.ByteString deriving (JSON.ToJSON, Typeable)

validTag :: Regex.Regex
validTag = Regex.makeRegex
  ("^[a-z][-a-z ]+[a-z]$" :: BS.ByteString)

validateTag :: BS.ByteString -> Maybe TagName
validateTag t = Regex.matchTest validTag tt ?> TagName tt where
  tt = BSC.unwords $ BSC.words t

instance PathDynamic TagName where
  pathDynamic = validateTag <=< pathDynamic
  dynamicPath (TagName n) = dynamicPath n

instance PGParameter "character varying" TagName where
  pgEncode t (TagName n) = pgEncode t n
  pgEncodeValue e t (TagName n) = pgEncodeValue e t n
  pgLiteral t (TagName n) = pgLiteral t n
instance PGColumn "character varying" TagName where
  pgDecode t = TagName . pgDecode t
  pgDecodeValue e t = TagName . pgDecodeValue e t

type instance IdType Tag = Int32

data Tag = Tag
  { tagId :: Id Tag
  , tagName :: TagName
  }

makeHasRec ''Tag ['tagId, 'tagName]

instance Kinded Tag where
  kindOf _ = "tag"

data TagUse = TagUse
  { useTag :: Tag
  , tagKeyword :: Bool
  , tagWho :: Account
  , tagSlot :: Slot
  }

makeHasRec ''TagUse ['useTag, 'tagWho, 'tagSlot]

data TagWeight = TagWeight
  { tagWeightTag :: Tag
  , tagWeightWeight :: Int32
  }

makeHasRec ''TagWeight ['tagWeightTag]

data TagCoverage = TagCoverage
  { tagCoverageWeight :: !TagWeight
  , tagCoverageContainer :: Container
  , tagCoverageSegments
  , tagCoverageKeywords
  , tagCoverageVotes :: [Segment]
  }

makeHasRec ''TagCoverage ['tagCoverageWeight, 'tagCoverageContainer]