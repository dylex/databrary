{-# LANGUAGE OverloadedStrings, TemplateHaskell, RecordWildCards #-}
module Databrary.Model.Record
  ( module Databrary.Model.Record.Types
  , lookupRecord
  , recordJSON
  ) where

import Control.Applicative ((<$>))
import Data.Maybe (catMaybes)
import qualified Data.Text as T

import Control.Has (peek, see)
import Databrary.DB
import qualified Databrary.JSON as JSON
import Databrary.Model.SQL (selectQuery)
import Databrary.Model.Id
import Databrary.Model.Permission
import Databrary.Model.Identity.Types
import Databrary.Model.Volume.Types
import Databrary.Model.Party.Types
import Databrary.Model.RecordCategory
import Databrary.Model.Metric
import Databrary.Model.Record.Types
import Databrary.Model.Record.SQL

useTPG

lookupRecord :: (MonadHasIdentity c m, DBM m) => Id Record -> m (Maybe Record)
lookupRecord i = do
  ident <- peek
  dbQuery1 $ $(selectQuery (selectRecord 'ident) "$WHERE record.id = ${i}")

getRecordMeasures :: Record -> Measures
getRecordMeasures r = maybe [] filt $ readClassification (see r) (see r) where
  filt c = filter ((>= c) . see) $ recordMeasures r

measureJSONPair :: Measure -> JSON.Pair
measureJSONPair m = T.pack (show (metricId (measureMetric m))) JSON..= measureDatum m

recordJSON :: Record -> JSON.Object
recordJSON r@Record{..} = JSON.record recordId $ catMaybes
  [ Just $ "volume" JSON..= volumeId recordVolume
  , ("category" JSON..=) <$> fmap recordCategoryId recordCategory
  , Just $ "measures" JSON..= JSON.Object (JSON.object $ map measureJSONPair $ getRecordMeasures r)
  ]
