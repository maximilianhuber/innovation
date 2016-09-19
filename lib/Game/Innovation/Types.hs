{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
module Game.Innovation.Types
       where

import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Proxy
import           System.Random
import           System.Random.Shuffle (shuffle')
import           Control.Lens (makeLenses, Lens, Lens')
import qualified Control.Lens as L

import           Game.MetaGame

--------------------------------------------------------------------------------
-- Basic types
--------------------------------------------------------------------------------

data Color = Blue | Purple | Red | Yellow | Green
  deriving (Eq,Show,Read,Enum,Ord,Bounded)
colors :: [Color]
colors = [minBound ..]

data Age = Age1 | Age2 | Age3 | Age4 | Age5 | Age6 | Age7 | Age8 | Age9 | Age10
  deriving (Eq,Show,Read,Enum,Ord,Bounded)
ages :: [Age]
ages =  [minBound ..]

data Symbol = Castle | Tree | Crown | Bulb | Factory | Clock
  deriving (Eq,Show,Read,Enum,Ord,Bounded)

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

-- data Action
--   =  RawAction String
--   deriving (Eq,Show)

-- --------------------------------------------------------------------------------
-- -- Dogmas
-- --------------------------------------------------------------------------------

data Selector
  = Hand
  | Influence
  | StackOfColor Color
--   -- -| TheCard Card
--   -- Selector combinators
--   | OrSelector [Selector]
--   | AndSelector [Selector]
--   | OneOf Selector
--   | HalfOf Selector
--   | AllOf Selector
--   | UpTo Selector
  -- Raw
  | RawSelector String
  deriving (Eq,Show)

data DogmaDescription
  =
  --   D Action
  -- | DD Action Selector
  -- -- DogmaDescription combinators
  -- | YouMay DogmaDescription
  -- | AndAlsoDo DogmaDescription DogmaDescription
  -- -- Raw
    RawDescription String
  deriving (Eq,Show)

data Dogma
  = Dogma Symbol DogmaDescription
  | IDemand Symbol DogmaDescription
  deriving (Eq,Show)

--------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------

data Production
  = None
  | Produce { _prodSymbol :: Symbol }
  deriving (Eq,Show)
makeLenses ''Production

isSymbolProduction :: Production -> Bool
isSymbolProduction (Produce _) = True
isSymbolProduction _           = False


--   +----------------+
--   | tl             |
--   |                |
--   | bl    bc    br |
--   +----------------+
data Productions
  = Productions { _tlProd :: Production
                , _blProd :: Production
                , _bcProd :: Production
                , _brProd :: Production }
  deriving (Eq,Show)
makeLenses ''Productions

type CardId = String
data Card
  = Card { _color       :: Color
         , _age         :: Age
         , _productions :: Productions
         , _dogmas      :: [Dogma] }
  deriving (Eq,Show)
makeLenses ''Card

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

type Stack = [Card]
emptyStack = [] :: Stack

data SplayState
  = SplayedLeft
  | SplayedRight
  | SplayedUp
  | NotSplayed
  deriving (Eq,Show,Enum,Bounded)

data Player
  = Player { _playerId    :: UserId
           , _stacks      :: Map Color Stack
           , _splayStates :: Map Color SplayState
           , _influence   :: Stack
           , _dominations :: Stack
           , _hand        :: Stack }
  deriving (Show)
makeLenses ''Player

instance Eq Player where
  p1 == p2 = _playerId p1 == _playerId p2

instance UserC Player where
  getUserId = _playerId

--------------------------------------------------------------------------------
-- Game state
--------------------------------------------------------------------------------

data Choice = HasToChoose UserId Selector
            | HasChosen UserId Selector

data MachineState
  = Prepare
  | WaitForTurn
  | WaitForChoices [Choice]
  | FinishedGame GameResult

data State = State { _machineState :: MachineState
                   , _drawStacks   :: Map Age Stack
                   , _players      :: [Player]
                   , _playerOrder  :: PlayerOrder
                   , _history      :: Game State }
makeLenses ''State

instance StateC State where
  emptyState = State Prepare Map.empty [] [] (G [])

  getCurrentPlayer'  State{ _playerOrder=[] }    = Admin
  getCurrentPlayer'  State{ _playerOrder=order } = head order

  advancePlayerOrder = L.over playerOrder advancePlayerOrder'
    where
      advancePlayerOrder' :: PlayerOrder -> PlayerOrder
      advancePlayerOrder' []                       = []
      advancePlayerOrder' [p]                      = [p]
      advancePlayerOrder' (p1:(p2:ps)) | p1 == p2  = p2:ps
                                       | otherwise = p2:ps ++ [p1,p1]


does :: ActionC State actionToken =>
        UserId -> actionToken -> Action State
does = does' (Proxy :: Proxy State)

--------------------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------------------

mkPlayer :: String -> Player
mkPlayer playerId = Player (U playerId)
                           (Map.fromList $ zip colors $ repeat [])
                           (Map.fromList $ zip colors $ repeat NotSplayed)
                           []
                           []
                           []

shuffleState :: Int -> State -> State
shuffleState seed gs = gs{ _drawStacks=permutatedDS }
  where
    stdGen = mkStdGen seed
    shuffle []    = []
    shuffle stack = shuffle' stack (length stack) stdGen
    permutatedDS = Map.map shuffle $ _drawStacks gs
