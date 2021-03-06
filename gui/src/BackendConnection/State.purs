module BackendConnection.State where

import Prelude
import Signal.Channel
import WebSocket
import Data.Argonaut
import Data.Either
import Pux
import Data.Lens
import Control.Monad.Eff
import Global.Effects
import BackendConnection.Types (Action(..), State(..), socket)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Console (log)
import Control.Monad.Eff.Exception (EXCEPTION)
import Control.Monad.Eff.Var (($=))
import Debug.Trace (spy)

initialState :: ∀ a eff .
                DecodeJson a =>
                Channel (Action a) ->
                URL -> 
                Eff ( ws :: WEBSOCKET, err :: EXCEPTION | eff ) (State a)
initialState chan url = do
    connection@(Connection ws) <- newWebSocket url []
    ws.onopen $= connectToBackend ws
    ws.onmessage $= receiveMessage
    pure $ State
        { _events : chan
        , _socket : connection
        }
  where
    decodeReceived s = case jsonParser s of
        Right j -> j
        Left _ -> fromString ""
    connectToBackend ws _ = ws.send (Message "HaskellDO:Client")
    receiveMessage event = do
        let received = runMessage (runMessageEvent event)
        let nb = decodeJson (decodeReceived received) :: Either String a
        case nb of
            Left s ->
                send chan (NoOp :: Action a)
            Right n ->
                send chan ((Receive n) :: Action a)

sendMsg :: ∀ a e . Connection -> String -> Eff ( ws :: WEBSOCKET, err :: EXCEPTION | e ) (Action a)
sendMsg (Connection ws) msg = 
        ws.send (Message msg) *> pure NoOp

update :: ∀ a . EncodeJson a => Update (State a) (Action a) GlobalEffects
update (Send x) s = onlyEffects s $ [do
        let encodedX = encodeJson x
        let ws = view socket s
        liftEff $ sendMsg ws (spy $ show encodedX)
    ]
update _ s = noEffects $ s
