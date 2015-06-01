{-# LANGUAGE OverloadedStrings #-}
module Databrary.Controller.Container
  ( getContainer
  , viewContainer
  , viewContainerEdit
  , createContainer
  , postContainer
  , containerDownloadName
  ) where

import Control.Monad (mfilter)
import Data.Maybe (maybeToList)
import qualified Data.Text as T

import Databrary.Ops
import qualified Databrary.Iso as I
import Databrary.Has (view)
import Databrary.Model.Id
import Databrary.Model.Permission
import Databrary.Model.Volume
import Databrary.Model.Container
import Databrary.Model.Segment
import Databrary.Model.Slot
import Databrary.Action
import Databrary.HTTP.Form.Deform
import Databrary.HTTP.Path.Parser
import Databrary.Controller.Paths
import Databrary.Controller.Permission
import Databrary.Controller.Form
import Databrary.Controller.Angular
import Databrary.Controller.Volume
import {-# SOURCE #-} Databrary.Controller.Slot
import Databrary.View.Container

getContainer :: Permission -> Maybe (Id Volume) -> Id Slot -> AuthActionM Container
getContainer p mv (Id (SlotId i s))
  | segmentFull s = checkPermission p =<< maybeAction . maybe id (\v -> mfilter $ (v ==) . view) mv =<< lookupContainer i
  | otherwise = result =<< notFoundResponse

containerDownloadName :: Container -> [T.Text]
containerDownloadName c = maybeToList $ containerName c

viewContainer :: AppRoute (API, (Maybe (Id Volume), Id Container))
viewContainer = I.second (I.second $ slotContainerId . unId I.:<->: containerSlotId) I.<$> viewSlot

containerForm :: (Functor m, Monad m) => Container -> DeformT m Container
containerForm c = do
  name <- "name" .:> deformNonEmpty deform
  date <- "date" .:> deformNonEmpty deform
  release <- "release" .:> deformNonEmpty deform
  return c
    { containerName = name
    , containerDate = date
    , containerRelease = release
    }

viewContainerEdit :: AppRoute (Maybe (Id Volume), Id Slot)
viewContainerEdit = action GET (pathHTML >/> pathMaybe pathId </> pathSlotId </< "edit") $ \(vi, ci) -> withAuth $ do
  angular
  c <- getContainer PermissionEDIT vi ci
  blankForm $ htmlContainerForm (Right c)

createContainer :: AppRoute (API, Id Volume)
createContainer = action POST (pathAPI </> pathId </< "slot") $ \(api, vi) -> withAuth $ do
  vol <- getVolume PermissionEDIT vi
  bc <- runForm (api == HTML ?> htmlContainerForm (Left vol)) $ do
    top <- "top" .:> deform
    containerForm (blankContainer vol)
      { containerTop = top }
  c <- addContainer bc
  case api of
    JSON -> okResponse [] $ containerJSON c
    HTML -> redirectRouteResponse [] viewContainer (api, (Just vi, containerId c)) []

postContainer :: AppRoute (API, Id Slot)
postContainer = action POST (pathAPI </> pathSlotId) $ \(api, ci) -> withAuth $ do
  c <- getContainer PermissionEDIT Nothing ci
  c' <- runForm (api == HTML ?> htmlContainerForm (Right c)) $ containerForm c
  changeContainer c'
  case api of
    JSON -> okResponse [] $ containerJSON c'
    HTML -> redirectRouteResponse [] viewSlot (api, (Just (view c'), ci)) []
