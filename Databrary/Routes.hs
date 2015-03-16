{-# LANGUAGE OverloadedStrings #-}
module Databrary.Routes
  ( routes
  ) where

import qualified Data.ByteString as BS
import Control.Applicative ((<|>))
import Control.Monad (msum, guard)
import Control.Monad.Reader (ask)
import Network.HTTP.Types (methodGet, movedPermanently301, hLocation)
import qualified Network.Wai as Wai

import qualified Databrary.Web.Route as R
import Databrary.Action
import Databrary.Action.Types
import Databrary.Controller.Root
import Databrary.Controller.Login
import Databrary.Controller.Register
import Databrary.Controller.Token
import Databrary.Controller.Party
import Databrary.Controller.Authorize
import Databrary.Controller.Volume
import Databrary.Controller.VolumeAccess
import Databrary.Controller.Container
import Databrary.Controller.Record
import Databrary.Controller.Citation
import Databrary.Controller.Upload
import Databrary.Controller.Asset
import Databrary.Controller.Excerpt
import Databrary.Controller.Tag
import Databrary.Controller.Angular
import Databrary.Controller.Static

act :: ActionData q => RouteAction q -> R.RouteM (Action q)
act ra = do
  R.final
  req <- ask
  guard $ actionMethod ra == Wai.requestMethod req
  return $
    if actionMethod ra == methodGet && Wai.rawPathInfo req /= actionRoute ra
      then emptyResponse movedPermanently301 [(hLocation, actionURL ra (Just req) `BS.append` Wai.rawQueryString req)]
      else routeAction ra

routes :: R.RouteM AppAction
routes = do
  api <- R.route
  let
    json = guard (api == JSON)
    html = guard (api == HTML)
  msum 
    [                                 act (viewRoot api)
    , "user" >> msum                  -- /user
      [                      (html >> act viewUser)
      ,                               act (postUser api)
      , "login" >>           (html >> act viewLogin)
                                  <|> act (postLogin api)
      , "logout" >>                   act (postLogout api)
      , "register" >>        (html >> act viewRegister)
                                  <|> act (postRegister api)
      , "password" >>        (html >> act viewPasswordReset)
                                  <|> act (postPasswordReset api)
      ]
    , R.route >>= \t ->               -- /token/ID
                                      act (viewLoginToken api t)
                                  <|> act (postPasswordToken api t)
    , R.route >>= \p -> msum          -- /party/ID
      [                               act (viewParty api p)
      ,                               act (postParty api p)
      , html >> "edit" >>             act (viewPartyForm p)
      , R.route >>= \a -> msum        --          /authorize/ID
        [                             act (viewAuthorize api p a)
        ,                             act (postAuthorize api p a)
        ,                             act (deleteAuthorize api p a)
        ]
      ]
    , "party" >>                      act (createParty api)
                                  <|> act (searchParty api)
    , R.route >>= \v -> msum          -- /vo/ume/ID
      [                               act (viewVolume api v)
      ,                               act (postVolume api v)
      , html >> "edit" >>             act (viewVolumeForm v)
      , R.route >>= \p ->             --           /access/ID
                             (html >> act (viewVolumeAccess v p))
                                  <|> act (postVolumeAccess api v p)
      , "link" >>            (html >> act (viewVolumeLinks v))
                                  <|> act (postVolumeLinks api v)
      , "container" >>                act (createContainer api v)
      , "record" >>                   act (createRecord api v)
      , "asset" >>                    act (createAsset api v)
      , json >> "upload" >>           act (uploadStart v)
      ]
    , "volume" >>                     act (createVolume api)

    , R.route >>= \c -> msum          -- /container/ID
      [                               act (viewContainer api c)
      ,                               act (postContainer api c)
      ]

    -- , R.route >>= \s -> msum          -- /slot/ID/SEG

    , R.route >>= \r -> msum          -- /record/ID
      [                               act (viewRecord api r)
      , R.route >>= \m ->             act (postRecordMeasure api r m)
      ]

    , R.route >>= \a -> msum          -- /asset/ID
      [                               act (viewAsset api a)
      ,        (html >> "download" >> act (downloadAsset a))
      ,         (json >> "excerpt" >> act (postExcerpt a)
                                  <|> act (deleteExcerpt a))
      ]

    , json >> msum                    -- /api
      [ "cite" >>                     act getCitation
      , "upload" >>                   act uploadChunk
                                  <|> act testChunk
      ]

    , html >> msum                    -- /
      [ "public" >> R.route >>=       act . staticPublicFile
      , "constants.js" >>             act angularConstants
      ]
    ]
