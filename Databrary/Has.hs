{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, ConstraintKinds, TemplateHaskell, TypeSynonymInstances, LiberalTypeSynonyms #-}
module Databrary.Has
  ( Has(..)
  , MonadHas
  , peek
  , peeks
  , focusReaderT
  , focusReader
  , focusLift
  , focusBase
  , focusIO
  , makeHasFor
  , makeHasRec
  ) where

import Control.Applicative (Applicative)
import Control.Monad (unless, liftM, liftM2)
import Control.Monad.Base (MonadBase(..))
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Reader (MonadReader, ReaderT(..), reader, withReaderT)
import Control.Monad.Trans.Class (MonadTrans(..))
import Data.List (foldl')
import qualified Language.Haskell.TH as TH

class Has a c where
  view :: c -> a

instance Has a a where
  view = id

type MonadHas a c m = (Functor m, Applicative m, MonadReader c m, Has a c)

{-# INLINE peek #-}
peek :: (MonadReader c m, Has a c) => m a
peek = reader view

{-# INLINE peeks #-}
peeks :: (MonadReader c m, Has a c) => (a -> b) -> m b
peeks f = reader (f . view)

{-# INLINE focusReaderT #-}
focusReaderT :: (Monad m, Has a c) => ReaderT a m r -> ReaderT c m r
focusReaderT = withReaderT view

{-# INLINE focusReader #-}
focusReader :: (Monad m, Has a c) => (a -> m b) -> ReaderT c m b
focusReader f = ReaderT (f . view)

{-# INLINE focusLift #-}
focusLift :: (MonadTrans t, Monad m, MonadHas a c (t m)) => (a -> m b) -> t m b
focusLift f = lift . f =<< peek

{-# INLINE focusBase #-}
focusBase :: (MonadBase t m, MonadHas a c m) => (a -> t b) -> m b
focusBase f = liftBase . f =<< peek

{-# INLINE focusIO #-}
focusIO :: (MonadIO m, MonadHas a c m) => (a -> IO b) -> m b
focusIO f = liftIO . f =<< peek

getFieldType :: TH.Name -> TH.Name -> TH.TypeQ
getFieldType tn fn = do
  TH.VarI _ (TH.ArrowT `TH.AppT` TH.ConT tn' `TH.AppT` ft) _ _ <- TH.reify fn
  unless (tn' == tn) $ fail $ show tn ++ "." ++ show fn ++ ": field from wrong type: " ++ show tn'
  return ft

makeHasFor :: TH.Name -> [(TH.Name, [TH.Type])] -> TH.DecsQ
makeHasFor tn fs = concatM
  (return
    [ TH.TySynD ht [TH.PlainTV cv] $ tupleT $
        map (\t -> TH.ConT ''Has `TH.AppT` t `TH.AppT` TH.VarT cv) (tt : concatMap snd fs)
    , TH.TySynD (TH.mkName ("MonadHas" ++ TH.nameBase tn)) [TH.PlainTV cv, TH.PlainTV mv] $ tupleT $
        [ TH.ConT ''Functor `TH.AppT` TH.VarT mv
        , TH.ConT ''Applicative `TH.AppT` TH.VarT mv
        , TH.ConT ''MonadReader `TH.AppT` TH.VarT cv `TH.AppT` TH.VarT mv
        , TH.ConT ht `TH.AppT` TH.VarT cv
        ]
    ])
  (\(fn, ts) -> do
    ft <- getFieldType tn fn
    concatM
      [d| instance Has $(return ft) $(return tt) where
            view = $(TH.varE fn) |]
      (\st ->
        [d| instance Has $(return st) $(return tt) where
              view = view . $(TH.varE fn) |])
      ts)
  fs
  where
  tt = TH.ConT tn
  ht = TH.mkName ("Has" ++ TH.nameBase tn)
  cv = TH.mkName "c"
  mv = TH.mkName "m"
  concatM i f l = liftM2 (++) i (liftM concat $ mapM f l)
  tupleT l = foldl' TH.AppT (TH.TupleT (length l)) l

makeHasRec :: TH.Name -> [TH.Name] -> TH.DecsQ
makeHasRec tn fs = do
  TH.ClassI _ il <- TH.reify ''Has
  makeHasFor tn =<< mapM (\fn -> do
    ft <- getFieldType tn fn
    return (fn, [ st
      | TH.InstanceD _ (TH.ConT hs `TH.AppT` st `TH.AppT` ft') _ <- il
      , hs == ''Has
      , ft' == ft 
      ]))
    fs