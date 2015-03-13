{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Databrary.Model.Time.Types
  ( Date
  , Timestamp
  , Offset
  , Segment
  , Age(..)
  ) where

import qualified Data.Time

import Database.PostgreSQL.Typed.Range (Range)

type Date = Data.Time.Day
type Timestamp = Data.Time.UTCTime
type Offset = Data.Time.DiffTime
type Segment = Range Offset
newtype Age = Age { ageDays :: Int } deriving (Eq, Ord, Num)
