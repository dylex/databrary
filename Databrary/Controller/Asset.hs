{-# LANGUAGE OverloadedStrings #-}
module Databrary.Controller.Asset
  ( getAsset
  , viewAsset
  , postAsset
  , createAsset
  , deleteAsset
  , downloadAsset
  ) where

import Control.Applicative ((<|>))
import Control.Monad ((<=<), when, void)
import Control.Monad.Trans.Class (lift)
import qualified Data.ByteString as BS
import Data.Either (isLeft, isRight)
import Data.Maybe (fromMaybe, fromJust, isNothing, isJust)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Traversable as Trav
import qualified Database.PostgreSQL.Typed.Range as Range
import Network.HTTP.Types (StdMethod(DELETE), conflict409)
import qualified Network.Wai as Wai
import Network.Wai.Parse (FileInfo(..))

import Databrary.Ops
import Databrary.Has (peeks)
import Databrary.ResourceT
import qualified Databrary.JSON as JSON
import Databrary.DB
import Databrary.Web.Form
import Databrary.Web.Form.Errors
import Databrary.Web.Form.Deform
import Databrary.Web.File
import Databrary.Action
import Databrary.Model.Segment
import Databrary.Model.Permission
import Databrary.Model.Id
import Databrary.Model.Identity
import Databrary.Model.Volume
import Databrary.Model.Container
import Databrary.Model.Token
import Databrary.Model.Format
import Databrary.Model.Asset
import Databrary.Model.Slot
import Databrary.Model.AssetSlot
import Databrary.Model.Excerpt
import Databrary.Store
import Databrary.Store.Types
import Databrary.Store.Asset
import Databrary.Store.Upload
import Databrary.Store.Temp
import Databrary.Controller.Permission
import Databrary.Controller.Form
import Databrary.Controller.Volume
import Databrary.Controller.Angular
import Databrary.View.Asset

getAsset :: Permission -> Id Asset -> AuthActionM AssetSlot
getAsset p i =
  checkPermission p =<< maybeAction =<< lookupAssetSlot i

assetJSONField :: (DBM m, MonadHasIdentity c m) => AssetSlot -> BS.ByteString -> Maybe BS.ByteString -> m (Maybe JSON.Value)
assetJSONField a "excerpts" _ =
  Just . JSON.toJSON . map excerptJSON <$> lookupAssetExcerpts a
assetJSONField _ _ _ = return Nothing

assetJSONQuery :: (DBM m, MonadHasIdentity c m) => AssetSlot -> JSON.Query -> m JSON.Object
assetJSONQuery vol = JSON.jsonQuery (assetSlotJSON vol) (assetJSONField vol)

viewAsset :: API -> Id Asset -> AppRAction
viewAsset api i = action GET (api, i) $ withAuth $ do
  when (api == HTML) angular
  asset <- getAsset PermissionPUBLIC i
  case api of
    JSON -> okResponse [] =<< assetJSONQuery asset =<< peeks Wai.queryString
    HTML -> okResponse [] $ show $ assetId $ slotAsset asset -- TODO

data FileUpload
  = FileUploadForm
    { _fileUploadForm :: FileInfo TempFile
    , fileUploadFormat :: Format
    }
  | FileUploadToken
    { _fileUploadToken :: Upload
    , fileUploadFormat :: Format
    }

fileUploadName :: FileUpload -> BS.ByteString
fileUploadName (FileUploadForm f _) = fileName f
fileUploadName (FileUploadToken u _) = uploadFilename u

fileUploadPath :: FileUpload -> Storage -> RawFilePath
fileUploadPath (FileUploadForm f _) _ = tempFilePath $ fileContent f
fileUploadPath (FileUploadToken u _) s = uploadFile u s

fileUploadRemove :: (MonadResourceT c m, DBM m, MonadStorage c m) => FileUpload -> m ()
fileUploadRemove (FileUploadForm f _) = releaseTempFile $ fileContent f
fileUploadRemove (FileUploadToken u _) = void $ removeUpload u

deformLookup :: (Monad m, Functor m, Deform a) => FormErrorMessage -> (a -> m (Maybe b)) -> DeformT m (Maybe b)
deformLookup e l = Trav.mapM (deformMaybe' e <=< lift . l) =<< deform

processAsset :: API -> Either Volume AssetSlot -> AuthAction
processAsset api target = do
  (fd, ufs) <- getFormData [("file", maxAssetSize)]
  let as@AssetSlot{ slotAsset = a, assetSlot = s } = either (assetNoSlot . blankAsset) id target
  (as', upfile) <- runFormWith fd (api == HTML ?> htmlAssetForm target) $ do
    let file = lookup "file" ufs
    upload <- "upload" .:> deformLookup "Uploaded file not found." lookupUpload
    let ffmt = deformMaybe' "Unknown or unsupported file format." . getFormatByFilename
    upfile <- case (file, upload) of
      (Just f, Nothing) -> Just . FileUploadForm f <$> ffmt (fileName f)
      (Nothing, Just u) -> Just . FileUploadToken u <$> ffmt (uploadFilename u)
      (Nothing, Nothing) -> do
        when (isLeft target) $ deformError "File or upload required."
        return $ Nothing
      _ -> Nothing <$ deformError "Conflicting uploaded files found."
    let fmt = maybe (assetFormat a) fileUploadFormat upfile
    name <- "name" .:> fmap (dropFormatExtension fmt) <$> deform
    classification <- "classification" .:> deform
    slot <-
      "container" .:> (<|> slotContainer <$> s) <$> deformLookup "Container not found." (lookupVolumeContainer (assetVolume a))
      >>= Trav.mapM (\c -> "position" .:> do
        let seg = slotSegment <$> s
        p <- (<|> (lowerBound . segmentRange =<< seg)) <$> deform
        Slot c . maybe fullSegment
          (\l -> Segment $ Range.bounded l (l + fromMaybe 0 ((segmentLength =<< seg) <|> assetDuration a)))
          <$> orElseM p (flatMapM (lift . findAssetContainerEnd) (isNothing s && isJust (assetDuration a) ?> c)))
    return
      ( as
        { slotAsset = a
          { assetName = TE.decodeUtf8 <$> name
          , assetClassification = classification
          , assetFormat = fmt
          }
        , assetSlot = slot
        }
      , upfile
      )
  as'' <- maybe (return as') (\up -> do
    a' <- addAsset (slotAsset as')
      { assetName = Just $ TE.decodeUtf8 $ fileUploadName up
      } . Just =<< peeks (fileUploadPath up)
    fileUploadRemove up
    when (isRight target) $ supersedeAsset a a'
    return as'
      { slotAsset = a'
        { assetName = assetName (slotAsset as')
        }
      })
    upfile
  changeAsset (slotAsset as'')
  changeAssetSlot as''
  case api of
    JSON -> okResponse [] $ assetSlotJSON as''
    HTML -> redirectRouteResponse [] $ viewAsset api (assetId (slotAsset as''))

postAsset :: API -> Id Asset -> AppRAction
postAsset api ai = action POST (api, ai) $ withAuth $ do
  asset <- getAsset PermissionEDIT ai
  r <- assetIsSuperseded (slotAsset asset)
  guardAction (not r) $
    returnResponse conflict409 [] ("This file has already been replaced." :: T.Text)
  processAsset api (Right asset)

createAsset :: API -> Id Volume -> AppRAction
createAsset api vi = action POST (api, vi, "asset" :: T.Text) $ withAuth $ do
  v <- getVolume PermissionEDIT vi
  processAsset api $ Left v

deleteAsset :: API -> Id Asset -> AppRAction
deleteAsset api ai = action DELETE (api, ai) $ withAuth $ do
  asset <- getAsset PermissionEDIT ai
  let asset' = asset{ assetSlot = Nothing }
  changeAssetSlot asset'
  case api of
    JSON -> okResponse [] $ assetSlotJSON asset'
    HTML -> redirectRouteResponse [] $ viewAsset api (assetId (slotAsset asset'))

downloadAsset :: Id Asset -> AppRAction
downloadAsset ai = action GET (ai, "download" :: T.Text) $ withAuth $ do
  as <- getAsset PermissionREAD ai
  let a = slotAsset as
  store <- maybeAction =<< getAssetFile a
  auditAssetSlotDownload True as
  serveFile store (assetFormat a) (fromJust $ assetSHA1 a)
