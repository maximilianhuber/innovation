{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
module Game.MetaGame.Types.Game
       ( PlayerC
       , InnerMoveType, InnerMoveResult, runInnerMoveType
       , OuterMoveResult, liftFromInner, runOuterMoveType
       , MoveType, MoveResult
       , getObject, setObject, modifyObject
       , MoveWR (..), Move
       , ActionType, runActionType
       , ActionWR (..), Action, takes
       , ActionToken (..)
       , Turn (..)
       , Game (..)
       ) where

import           Prelude hiding (log)
import           Data.Monoid
import           Data.Text (Text)
import           Control.Monad.Trans
import           Control.Monad.Trans.Writer (Writer, WriterT)
import qualified Control.Monad.Trans.Writer as W
import           Control.Monad.Trans.Except (ExceptT)
import qualified Control.Monad.Trans.Except as E
import           Control.Monad.Trans.Reader (ReaderT)
import qualified Control.Monad.Trans.Reader as R
import           Control.Monad.Trans.State.Lazy (StateT)
import qualified Control.Monad.Trans.State.Lazy as S

import           Game.MetaGame.Types.Core hiding (getObject, setObject, modifyObject)
import qualified Game.MetaGame.Types.Core as Core
import           Game.MetaGame.Types.Board
import           Game.MetaGame.Types.Inquiry

--------------------------------------------------------------------------------
-- * Basic data and type declerations
--------------------------------------------------------------------------------

class (IdAble player) =>
      PlayerC player

--------------------------------------------------------------------------------
-- ** Moves
-- A move is the actual change on the board

type InnerMoveType board
  = ExceptT Text -- ^ uses ExceptT to communicate failures
    ( WriterT Log -- ^ uses WriterT to log
      ( Writer ( Game board ) ) ) -- ^ the history of the game

type InnerMoveResult board r
  = ( ( Either Text -- ^ this maybe contains the error text
        r -- ^ this is the calculated result
      , Log ) -- ^ this contains the log
    , Game board ) -- ^ the history of the game

runInnerMoveType :: InnerMoveType board a -> InnerMoveResult board a
runInnerMoveType = W.runWriter . W.runWriterT . E.runExceptT

data GameState board
  = GameState World MachineState
type MoveType board
  = StateT (GameState board) -- ^ uses StateT to handle the state of the board end everything else
    ( InquiryLayer board
                   ( InnerMoveType board ) )
getMachineState :: MoveType board MachineState
getMachineState = S.gets (\(GameState _ ms) -> ms)
getWorld :: MoveType board World
getWorld = S.gets (\(GameState w _) -> w)

liftFromInner :: InnerMoveType s a -> MoveType s a
liftFromInner = lift . lift . lift

type OuterMoveResult board r
  = InquiryResult board ( r -- ^ this is the calculated result
                        , World ) -- ^ this is the state of the board at the end of the calculation

type MoveResult board r = InnerMoveResult board (OuterMoveResult board r)

runOuterMoveType :: IdAble board =>
                    World -> [Answer] -> MoveType board r -> InnerMoveType board (OuterMoveResult board r)
runOuterMoveType w as move = E.runExceptT
                             ( S.runStateT
                               ( S.runStateT move w)
                               as )

-- | Something of MoveType can be applied to an inital board state
runMoveType :: IdAble board =>
               World -> [Answer] -> MoveType board a -> MoveResult board a
runMoveType os cs = runInnerMoveType . runOuterMoveType os cs

-- | The wrapper for a move
-- a 'MoveWR' is a 'Move' which returns something
newtype MoveWR board r
  = M {unpackMove :: MoveType board r}
-- | a 'Move' does not calculate anything, it just modifies the state (+ failures + log)
type Move board
  = MoveWR board ()

runMove :: IdAble board =>
           World -> [Answer] -> MoveWR board a -> MoveResult board a
runMove os as = runMoveType os as . unpackMove

instance BoardC board =>
         Monoid (Move board) where
  mempty                = M $ S.modify id -- TODO
  mappend (M t1) (M t2) = M $ t1 >> t2

instance BoardC board =>
         Functor (MoveWR board) where
  fmap f move = move >>= (return . f)

instance BoardC board =>
         Applicative (MoveWR board) where
  pure r = M $ return r
  (M getF) <*> (M getX) = M $ do
    r <- getF
    x <- getX
    return $ r x

instance BoardC board =>
         Monad (MoveWR board) where
  return t    = M $ return t
  (M t) >>= f = M $ t >>= (unpackMove . f)

--------------------------------------------------------------------------------
-- ** State helper

getObject :: IdAble a =>
        IdF a -> MoveType board a
getObject idA = do
  maybeA <- S.gets (Core.getObject idA)
  case maybeA of
    Just a -> return a
    Nothing -> undefined -- TODO

setObject :: IdAble a =>
             a -> MoveType board ()
setObject a = S.modify (Core.setObject a)

modifyObject :: IdAble a =>
             (a -> a) -> IdF a -> MoveType board ()
modifyObject f idA = S.modify (Core.modifyObject f idA)

--------------------------------------------------------------------------------
-- ** Actions
-- An action is something a player can take and it results in a move on the board

type ActionType board
  = ReaderT UserId -- ^ the user doing the action (also the logging user, ...)
            ( MoveType board ) -- ^ the move behind the action

runActionType :: UserId -> ActionType board r -> MoveType board r
runActionType = flip R.runReaderT

newtype ActionWR board r = A { unpackAction :: ActionType board r }
type Action board = ActionWR board ()

takes :: UserId -> ActionWR board r -> MoveType board r
takes uid = runActionType uid . unpackAction

instance Monoid (Action board) where
  mempty                = A (return mempty)
  mappend (A a1) (A a2) = A (a1 >> a2)

instance Functor (ActionWR board) where
  fmap f action = action >>= (return . f)

instance Applicative (ActionWR board) where
  pure r = A (return r)
  (A getF) <*> (A getX) = A (getF <*> getX)

instance Monad (ActionWR board) where
  return t    = A (return t)
  (A t) >>= f = A (t >>= (unpackAction . f))


--------------------------------------------------------------------------------
-- ** ActionTokens
-- ActionTokens are used to identify actions

-- | an actionToken is something which
--   - has a Read and a Show instance
--   - knows its corresponding action
class (BoardC board, View actionToken, Eq actionToken, Read actionToken, Show actionToken) =>
      ActionToken board actionToken where
  -- | returns the action corresponding to an Token
  getAction :: actionToken -> Action board

  -- | returns, whether the board is within an state, where the turn can be applied
  stateMatchesExpectation :: actionToken -> MoveType board Bool
  stateMatchesExpectation _ = do
    ms <- getObject (MachineStateId :: IdF MachineState)
    return (ms == WaitForTurn)

--------------------------------------------------------------------------------
-- ** Turns
-- A turn is the choice of an action, taken by an player

-- | A turn is a action which is taken by some player
-- TODO: Might be better called 'Action' since "one has two actions per turn"
data Turn board
  = forall actionToken.
    ActionToken board actionToken =>
    Turn { getActingPlayer :: UserId
         , getActionToken :: actionToken
         , answers :: [Answer] }

instance Show (Turn board) where
  show (Turn Admin actionToken choices)      = show actionToken ++ show choices
  show (Turn (U userId) actionToken choices) = userId ++ ": " ++ show actionToken ++ show choices
  show (Turn Guest _ _)                      = error "Guest is not allowed to have an turn"

instance View (Turn board) where
  view (Turn uid actionToken choices) = chownLE uid ((view uid <>> ": ") <> view actionToken) -- <>> ("[" ++ show choices ++ "]")

-- | The `Eq` instance of `Action board` is deriven from the `Show` instance
instance Eq (Turn board) where
  turn1 == turn2 = getActingPlayer turn1 == getActingPlayer turn2
                   && show turn1 == show turn2

--------------------------------------------------------------------------------
-- ** Game

type History board
  = [Turn board]

-- | A game consists of all the turns, i.e. taken actions, in chronological order
-- the last taken action is the head
newtype Game board
  = G (History board)
  deriving (Show)

instance Monoid (Game board) where
  mempty                = G []
  mappend (G g2) (G g1) = G $ mappend g1 g2
