module Game.Innovation.Cards
    ( cards
    ) where

import Data.Map (Map)
import qualified Data.Map as Map

import Game.Innovation.Types

cards :: Map Age Stack
cards = Map.fromList
        [(Age1,[agriculture])
        ,(Age2,[])
        ,(Age3,[])
        ,(Age4,[])
        ,(Age5,[])
        ,(Age6,[])
        ,(Age7,[])
        ,(Age8,[])
        ,(Age9,[])
        ,(Age10,[])]

--------------------------------------------------------------------------------
-- Age1 Cards
--------------------------------------------------------------------------------

agriculture =
  Card { _color       = Yellow
       , _age         = Age1
       , _productions = Productions None (Produce Tree) (Produce Tree) (Produce Tree)
       , _dogmas      =
         [Tree `Dogma` (RawDescription "You may recycle a card from your Hand. If you dou, draw and score a card of value one higher than the card you recycled")]
       }
--------------------------------------------------------------------------------
-- Age2 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age3 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age4 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age5 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age6 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age7 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age8 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age9 Cards
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Age10 Cards
--------------------------------------------------------------------------------
