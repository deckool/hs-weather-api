{-# LANGUAGE Arrows, NoMonomorphismRestriction #-}
module WeatherApi.Google (initApi) where

import Text.XML.HXT.Core
import Network.HTTP
import Network.URI
import WeatherApi

apiUrl  = "http://www.google.com/ig/api?"

type Lang = String
type Enc  = String

initApi :: Lang -> Enc -> Config
initApi   lang   enc =
    let params = [("hl", lang), ("oe", enc)]
        urn    = \c -> urlEncodeVars $ params ++ [("weather", c)]
    in Config { apiHost  = "www.google.com"
              , apiPort  = 80
              , queryFun = makeQueryFun urn
              }

retrieve s urn =
    case parseURI $ apiUrl ++ urn of
      Nothing  -> return $ Left "Invalid URL"
      Just uri -> get s uri

get s uri =
    do
      eresp <- sendHTTP s (Request uri GET [] "")
      case eresp of
        Left err  -> return $ Left $ show err
        Right res -> return $ Right $ rspBody res

atTag tag = deep (isElem >>> hasName tag)
dataAtTag tag = atTag tag >>> getAttrValue "data"

parseWeather = atTag "current_conditions" >>>
  proc x -> do
    tempF'         <- dataAtTag "temp_f"         -< x
    tempC'         <- dataAtTag "temp_c"         -< x
    humidity'      <- dataAtTag "humidity"       -< x
    windCondition' <- dataAtTag "wind_condition" -< x
    condition'     <- dataAtTag "condition"      -< x
    returnA -< Weather
      { tempF         = read tempF'
      , tempC         = read tempC'
      , humidity      = humidity'
      , windCondition = windCondition'
      , condition     = condition'
      }

parseXML doc = readString [ withValidate no
                          , withRemoveWS yes
                          ] doc

makeQueryFun q = \stream city -> do
      resp <- retrieve stream $ q city
      xml  <- return $ (resp >>= return . parseXML)
      case xml of
        Left a  -> return $ Left a
        Right a -> do
                 r <- runX(a >>> parseWeather)
                 case r of
                   [] -> return $ Left "can't retrieve weather"
                   (x:xs) -> return $ Right x
