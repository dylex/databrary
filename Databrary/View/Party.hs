{-# LANGUAGE OverloadedStrings, RecordWildCards #-}
module Databrary.View.Party
  ( htmlPartyView
  , htmlPartyEdit
  , htmlPartySearch
  , htmlPartyAdmin
  , htmlPartyDelete
  ) where

import Control.Monad (when, forM_, void)
import qualified Data.ByteString.Char8 as BSC
import Data.Maybe (fromMaybe)
import Data.Monoid ((<>))
import Network.HTTP.Types (toQuery)
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as HA

import Databrary.Has (view)
import Databrary.Model.Permission
import Databrary.Model.Party
import Databrary.Model.ORCID
import Databrary.Store.Temp
import Databrary.Action.Types
import Databrary.Action
import Databrary.Controller.Paths
import Databrary.View.Html
import Databrary.View.Template
import Databrary.View.Form
import Databrary.View.Paginate

import {-# SOURCE #-} Databrary.Controller.Angular
import {-# SOURCE #-} Databrary.Controller.Party
import {-# SOURCE #-} Databrary.Controller.Volume
import {-# SOURCE #-} Databrary.Controller.Register

htmlPartyView :: Party -> RequestContext -> H.Html
htmlPartyView p@Party{..} req = htmlTemplate req (Just $ partyName p) $ \js -> do
  when (view p >= PermissionEDIT) $
    H.p $
      H.a H.! actionLink viewPartyEdit (TargetParty partyId) js $ "edit"
  H.img
    H.! HA.src (builderValue $ actionURL Nothing viewAvatar partyId [])
  H.dl $ do
    forM_ partyAffiliation $ \a -> do
      H.dt "affiliation"
      H.dd $ H.text a
    forM_ partyURL $ \u -> do
      let us = show u
      H.dt "url"
      H.dd $ H.a H.! HA.href (H.stringValue us) $ H.string us
    forM_ (partyEmail p) $ \e -> do
      H.dt "email"
      H.dd $ H.a H.! HA.href (byteStringValue $ "mailto:" <> e) $ byteStringHtml e
    forM_ partyORCID $ \o -> do
      H.dt "orcid"
      H.dd $ H.a H.! HA.href (H.stringValue $ show $ orcidURL o) $ H.string $ show o
  H.a H.! actionLink queryVolumes HTML (toQuery js <> [("party", Just $ BSC.pack $ show partyId)]) $ "volumes"
  return ()

htmlPartyForm :: Maybe Party -> FormHtml TempFile
htmlPartyForm t = do
  field "prename" $ inputText $ partyPreName =<< t
  field "sortname" $ inputText $ partySortName <$> t
  field "affiliation" $ inputText $ partyAffiliation =<< t
  field "url" $ inputText $ show <$> (partyURL =<< t)

htmlPartyEdit :: Maybe Party -> RequestContext -> FormHtml TempFile
htmlPartyEdit t = maybe
  (htmlForm "Create party" createParty HTML)
  (\p -> htmlForm
    ("Edit " <> partyName p)
    postParty (HTML, TargetParty (partyId p)))
  t
  (htmlPartyForm t)
  (const mempty)

htmlPartyList :: JSOpt -> [Party] -> H.Html
htmlPartyList js pl = H.ul $ forM_ pl $ \p -> H.li $ do
  H.h2
    $ H.a H.! actionLink viewParty (HTML, TargetParty (partyId p)) js
    $ H.text $ partyName p
  mapM_ H.text $ partyAffiliation p

htmlPartySearchForm :: PartyFilter -> FormHtml f
htmlPartySearchForm pf = do
  field "query" $ inputText $ partyFilterQuery pf
  field "authorization" $ inputEnum False $ partyFilterAuthorization pf
  field "institution" $ inputCheckbox $ fromMaybe False $ partyFilterInstitution pf

htmlPartySearch :: PartyFilter -> [Party] -> RequestContext -> FormHtml f
htmlPartySearch pf pl req = htmlForm "Search users" queryParties HTML
  (htmlPartySearchForm pf)
  (\js -> htmlPaginate (htmlPartyList js) (partyFilterPaginate pf) pl (view req))
  req

htmlPartyAdmin :: PartyFilter -> [Party] -> RequestContext -> FormHtml f
htmlPartyAdmin pf pl req = htmlForm "party admin" adminParties ()
  (htmlPartySearchForm pf)
  (\js -> htmlPaginate
    (\pl' -> H.table $ do
      H.thead $
        H.tr $ do
          H.th "id"
          H.th "name"
          H.th "email"
          H.th "affiliation"
          H.th "act"
      H.tbody $
        forM_ pl' $ \p@Party{..} -> H.tr $ do
          H.td $ H.a H.! actionLink viewParty (HTML, TargetParty partyId) js
            $ H.string $ show partyId
          H.td $ H.text $ partyName p
          H.td $ mapM_ (byteStringHtml . accountEmail) partyAccount
          H.td $ mapM_ H.text partyAffiliation
          H.td $ do
            actionForm resendInvestigator partyId js
              $ H.input H.! HA.type_ "submit" H.! HA.value "agreement"
            H.a H.! actionLink viewPartyDelete partyId js
              $ "delete"
    )
    (partyFilterPaginate pf) pl (view req))
  req

htmlPartyDelete :: Party -> RequestContext -> FormHtml f
htmlPartyDelete p@Party{..} = htmlForm ("delete " <> partyName p)
  deleteParty partyId
  (return ())   
  (\js -> void $ H.a H.! actionLink viewParty (HTML, TargetParty partyId) js
    $ H.text $ partyName p)
