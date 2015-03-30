{-# LANGUAGE OverloadedStrings, RecordWildCards, TemplateHaskell, QuasiQuotes #-}
module Databrary.Model.Transcode
  ( module Databrary.Model.Transcode.Types
  , lookupTranscode
  , addTranscode
  , updateTranscode
  ) where

import qualified Data.ByteString as BS
import Data.Maybe (fromMaybe)
import Database.PostgreSQL.Typed.Query (pgSQL)

import Databrary.DB
import Databrary.Has (view, peek)
import Databrary.Store
import Databrary.Store.Types
import Databrary.Store.Asset
import Databrary.Model.SQL
import Databrary.Model.Audit
import Databrary.Model.Id
import Databrary.Model.Party
import Databrary.Model.Identity
import Databrary.Model.Offset
import Databrary.Model.Segment
import Databrary.Model.Format
import Databrary.Model.Asset
import Databrary.Model.Transcode.Types
import Databrary.Model.Transcode.SQL

defaultTranscodeOptions :: TranscodeArgs
defaultTranscodeOptions = ["-vf", "pad=iw+mod(iw\\,2):ih+mod(ih\\,2)"]

transcodeArgs :: MonadStorage c m => Transcode -> m TranscodeArgs
transcodeArgs Transcode{..} = do
  Just f <- getAssetFile transcodeOrig
  return $
    [ "-f", unRawFilePath f
    , "-r" -- , actionURL ...
    , "--" ]
    ++ maybe [] (\l -> ["-ss", show l]) lb
    ++ maybe [] (\u -> ["-t", show $ u - fromMaybe 0 lb]) (upperBound rng)
    ++ transcodeOptions
  where
  rng = segmentRange transcodeSegment
  lb = lowerBound rng

lookupTranscode :: DBM m => Id Asset -> m (Maybe Transcode)
lookupTranscode a =
  dbQuery1 $(selectQuery selectTranscode "WHERE transcode.asset = ${a}")

addTranscode :: (MonadAudit c m, MonadStorage c m) => Asset -> Segment -> TranscodeArgs -> Maybe Offset -> m Transcode
addTranscode orig seg@(Segment rng) opts dur = do
  Identified sess <- peek
  let own = view sess
      Just fmt = formatTranscodable (assetFormat orig)
  a <- addAsset orig
    { assetFormat = fmt
    , assetDuration = dur
    , assetSHA1 = Nothing
    , assetSize = Nothing
    } Nothing
  dbExecute1' [pgSQL|INSERT INTO transcode (asset, owner, orig, segment, options) VALUES (${assetId a}, ${partyId $ accountParty own}, ${assetId orig}, ${seg}, ${map Just opts})|]
  dbExecute1 [pgSQL|UPDATE slot_asset SET asset = ${assetId a}, segment = segment(lower(segment) + ${fromMaybe 0 $ lowerBound rng}, COALESCE(lower(segment) + ${upperBound rng}, upper(segment))) WHERE asset = ${assetId orig}|]
  return Transcode
    { transcodeAsset = a
    , transcodeOwner = own
    , transcodeOrig = orig
    , transcodeSegment = seg
    , transcodeOptions = opts
    , transcodeProcess = Nothing
    , transcodeLog = Nothing
    }

updateTranscode :: DBM m => Transcode -> Maybe TranscodePID -> Maybe BS.ByteString -> m Transcode
updateTranscode tc pid logs = do
  r <- dbQuery1 [pgSQL|UPDATE transcode SET process = ${pid}, log = COALESCE(COALESCE(log || E'\\n', '') || ${logs}, log) WHERE asset = ${assetId $ transcodeAsset tc} AND COALESCE(process, 0) = ${fromMaybe 0 $ transcodeProcess tc} RETURNING log|]
  return $ maybe tc (\l -> tc
    { transcodeProcess = pid
    , transcodeLog = l
    }) r