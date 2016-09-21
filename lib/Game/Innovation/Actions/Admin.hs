{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
module Game.Innovation.Actions.Admin
    ( Init (..)
    , SetCardDeck (..)
    , Shuffle (..)
    , DrawDominations (..)
    , AddPlayer (..)
    , StartGame (..)
    ) where

import           Prelude hiding (log)
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Maybe
import           Data.Monoid
import           Control.Monad.Trans.Identity
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Writer (WriterT)
import qualified Control.Monad.Trans.Writer as W
import           Control.Monad.Trans.Except (ExceptT)
import qualified Control.Monad.Trans.Except as E
import           Control.Monad.Trans.State.Lazy (StateT)
import qualified Control.Monad.Trans.State.Lazy as S
import           Control.Lens

import           Game.MetaGame
import           Game.Innovation.Types
import           Game.Innovation.Cards
import           Game.Innovation.Rules

--------------------------------------------------------------------------------
-- Admin actions
--------------------------------------------------------------------------------
doesInSequence = undefined

-- | Init
-- Does:
--  - SetCardDeck
--  - Shuffle
--  - DrawDominations
data Init = Init DeckName Int
          deriving (Eq, Show, Read)
instance ActionToken Board Init where
  getAction (Init deckName seed) = onlyAdminIsAllowed $
                                   A $ \userId ->
  -- TODO:
  -- @
  -- userId `doesInSequence` [ SetCardDeck deckName
  --                         , Shuffle seed
  --                         , DrawDominations ]
  -- @
    turnsToTransition [ userId `does` SetCardDeck deckName
                        , userId `does` Shuffle seed
                        , userId `does` DrawDominations ]

-- | SetCardDeck
data SetCardDeck = SetCardDeck DeckName
                 deriving (Eq, Show, Read)
instance ActionToken Board SetCardDeck where
  getAction (SetCardDeck deckName) = onlyAdminIsAllowed $
                                   A $ \userId ->
    T ( do
           log $ "Use the \"" ++ deckName ++ "\" card deck"
           S.modify (\board -> board{ _drawStacks=getDeck deckName })
      )


-- | Shuffle
-- create an empty game using a given seed
data Shuffle = Shuffle Int
             deriving (Eq, Show, Read)
instance ActionToken Board Shuffle where
  getAction (Shuffle seed) = onlyAdminIsAllowed $
                             A $ \userId ->
    T ( do
           logForMe ("Shuffle with seed [" ++ show seed ++ "]")
             "Shuffle with seed [only visible for admin]"
           S.modify (shuffleState seed)
      )

data DrawDominations = DrawDominations
                     deriving (Eq, Show, Read)
instance ActionToken Board DrawDominations where
  getAction DrawDominations = onlyAdminIsAllowed $
                              A $ \userId ->
    T ( do
           log "Draw dominations"
           S.modify id -- TODO
      )

-- | AddPlayer
-- add an player with a given playerId to the game
data AddPlayer = AddPlayer String
               deriving (Eq, Show, Read)
instance ActionToken Board AddPlayer where
  getAction (AddPlayer playerId) = onlyAdminIsAllowed $
                                   A $ \userId ->
    T ( do
           log ("Add player: " ++ playerId)
           state <- S.get
           case view machineState state of
             Prepare -> do
               let newPlayer = mkPlayer playerId
               S.modify (const (players %~ (newPlayer :) $
                                state))
             _       -> logError "not in prepare state."
      )

-- | StartGame
-- finish preperations of the game
data StartGame = StartGame
               deriving (Eq, Show, Read)
instance ActionToken Board StartGame where
  getAction StartGame = onlyAdminIsAllowed $
                        A $ \userId ->
    (T ( do
            log "Start game"
            ps <- use players
            if length ps >= 2 && length ps <=4
              then do
              -- Ask for first card
              S.modify id -- TODO
              else logError "Numer of players is not valid"
       )) <>
    -- ... wait..
    (T ( do
            -- play chosen cards
            -- determine starting player
            ps <- use players
            playerOrder .= map getId ps -- FALSE!
            machineState .= WaitForTurn
       ))

data DropPlayer = DropPlayer UserId
                deriving (Eq, Show, Read)

data Undo = Undo
          deriving (Eq, Show, Read)
