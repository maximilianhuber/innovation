{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
module Game.Innovation.Rules.CoreActions
    where

import           Prelude hiding (log)
import qualified Data.Map as Map
import qualified Data.List as List
import           Data.Maybe
import           Control.Monad
import qualified Control.Monad.Trans.State.Lazy as S
import qualified Control.Lens as L
import qualified Control.Arrow as Arr

import           Game.Innovation.Types
import qualified Game.Innovation.TypesLenses as L
import           Game.Innovation.Rules.CoreRules
import           Game.Innovation.Rules.Helper

-- | do nothing
skip :: Action
skip = undefined -- (toA . logA) "skip"
data Skip = Skip
          deriving (Eq, Show, Read)
instance ActionToken Board Skip where
  getAction Skip = skip

instance View Skip

pushCards :: Stack a =>
             [Card] -> a -> a
pushCards cs = onRawStack (cs ++)

pushBottomCards :: Stack a =>
                   [Card] -> a -> a
pushBottomCards cs = onRawStack (++ cs)

popCards :: Stack a =>
            Int -> a -> ([Card], a)
popCards n a = ((\(cs, rs) -> (cs, setRawStack a rs)) . popCards' n . getRawStack) a
  where
    popCards' :: Int -> RawStack -> ([Card], RawStack)
    popCards' 0 rs     = ([], rs)
    popCards' _ []     = ([], [])
    popCards' n (r:rs) = (\(cs',rs') -> (r: cs', rs')) (popCards' (n-1) rs)

popCardsWith :: Stack a =>
                Int -> (Card -> Bool) -> a -> ([Card],a)
popCardsWith n p a = (Arr.second (setRawStack a)) (popCardsWith' n p (getRawStack a))
  where
    popCardsWith' 0 _ a      = ([], a)
    popCardsWith' _ _ []     = ([], [])
    popCardsWith' n b (r:rs) | b r       = (\(cs',rs') -> (r: cs', rs')) (popCardsWith' (n-1) b rs)
                             | otherwise = (\(cs',rs') -> (cs', r: rs')) (popCardsWith' (n-1) b rs)

popTheCard :: Stack a =>
              CardId -> a -> (Maybe Card, a)
popTheCard cid a = let
  (rs1,rs2) = List.partition (\c -> idOf c == cid) (getRawStack a) -- TODO: respects order??
  in (Arr.second (setRawStack a)) (case rs1 of
                                      [c] -> (Just c, rs2)
                                      []  -> (Nothing, rs2)
                                      _   -> undefined -- TODO: should not be reacheable
                                  )

popCard :: Stack a =>
           a -> ([Card], a)
popCard = popCards 1

pushCard :: Stack a =>
            Card -> a -> a
pushCard c = pushCards [c]

drawNOfAnd :: Int -> Age -> ActionWR [Card]
drawNOfAnd n age = fmap concat (replicateM n (drawOfAnd age))

-- | Try to draw an card of an specific age
drawOfAnd :: Age -> ActionWR [Card]
drawOfAnd inputAge = mkA $ \userId -> do
  drawAge <- getDrawAgeByAge inputAge
  case drawAge of
    Just age -> do
      stack <- S.gets (fromJust . Map.lookup age . _drawStacks)
      let (cards, rest) = popCard stack
      S.modify $ L.over L.drawStacks (Map.insert age rest)
      case cards of
        [card] -> do
          userId `loggsAnEntry` ("draw the card " <<> view card)
          return [card]
        []     -> logTODO "tried to draw above Age10, endgame..."
        _      -> logFatal "should not be reacheable"
    _        -> unpackMove doEndGame

-- | Try to draw an card of current age
drawAnd :: ActionWR [Card]
drawAnd = mkA $ \userId -> do
  playersAge <- getAgeOf userId
  userId `takes` drawOfAnd playersAge

drawNAnd :: Int -> ActionWR [Card]
drawNAnd n = fmap concat (replicateM n drawAnd)

putIntoHand :: [Card] -> Action
putIntoHand cards = mkA $ \userId ->
  modifyPlayer userId $ L.over L.hand (onRawStack (cards ++))

popTheCardsOfHand :: [CardId] -> ActionWR [Card]
popTheCardsOfHand cids = mkA $ \uid -> let
  popTheCardOfHand :: CardId -> MoveType Card
  popTheCardOfHand cid = do
    hand <- getHandOf uid
    let (mc, newHand) = popTheCard cid hand
    case mc of
      Just c -> do
        modifyPlayer uid $ \p -> p{ _hand=newHand }
        return c
      Nothing -> logError "card not in the hand"
  in mapM popTheCardOfHand cids

putIntoPlay :: [Card] -> Action
putIntoPlay cards = mkA $ \userId -> let
  put1IntoPlay :: Card -> MoveType ()
  put1IntoPlay card = do
    userId `loggsAnEntry` ("put the card " <<> view card <>> " into play")
    let color = _color card
    modifyPlayer userId $ L.over L.zone (Map.adjust (pushCard card) color)
  in mapM_ put1IntoPlay cards

score :: [Card] -> Action
score cards = mkA $ \userId ->
  modifyPlayer userId $ L.over L.influence (pushCards cards)

putTheHandCardsIntoPlay :: [CardId] -> Action
putTheHandCardsIntoPlay cards = popTheCardsOfHand cards >>= putIntoPlay

--------------------------------------------------------------------------------
-- * complex Actions

--------------------------------------------------------------------------------
-- ** Domination related Actions

dominateAge :: Age -> Action
dominateAge age = mkA $ \userId -> do
  influence <- getInfluenceOf userId
  if (influence < (5 * (fromEnum age) + 5))
    then logError $ (show userId) ++ "has not enougth influence (only " ++ show influence ++ ")"
    else do
    (mc, ds) <- S.gets ((popCardsWith 1 (\c -> _age c == age)) . (L.view L.dominateables))
    case mc of
      [c] -> do
        userId `loggs` ("dominate age " ++ show age)
        S.modify $ \b -> b { _dominateables=ds }
        modifyPlayer userId $ L.over L.dominations (addDomination (AgeDomination c))
      _   -> logError $ "there is no card of age " ++ show age ++ " dominateable"

--------------------------------------------------------------------------------
-- ** Dogma related Actions

getAffectedOrder :: [UserId] -> MoveType [UserId]
getAffectedOrder affected = let
  getOrder = do
    ps <- fmap List.nub (S.gets _playerOrder)
    case ps of
      (hp:tp) -> return (tp ++ [hp])
      []      -> return []
  in do
    order <- getOrder
    return (filter (`elem` affected) order)

runDogmasOfCard :: Card -> Action
runDogmasOfCard Card { _dogmas=ds } = runDogmas ds ()

runDogmas :: DogmaChain a () -> a -> Action
runDogmas EDogmaChain       _ = pure ()
runDogmas (DogmaChain d ds) a = do
  r <- runDogma d a
  runDogmas ds r

runDogma :: Monoid b =>
            DogmaWR a b -> a -> ActionWR b
runDogma dogma a = let
  symb = getDSymbol dogma
  comperator callersNum = case dogma of
    Dogma{}      -> (>= callersNum)
    GenDogma{}   -> (>= callersNum)
    IDemand{}    -> (< callersNum)
    GenIDemand{} -> (< callersNum)
  in mkA $ \uid -> do
    callersNum <- getProductionsForSymbolOf symb uid
    affected <- getUidsWith (comperator callersNum . productionsForSymbolOf symb)
    orderedAffected <- getAffectedOrder affected
    fmap mconcat (mapM (`takes` getDAction dogma a) orderedAffected)

activate  :: Color -> Action
activate color = mkA $ \userId -> do
  ps <- getPlayStackByColorOf color userId
  when (isEmptyStack ps)
    (logError $ "Stack of color " ++ show color ++ " is empty")
  let activeCard = (head . getRawStack) ps
  userId `loggsAnEntry` ("activate the card " <<> view activeCard)
  userId `takes` runDogmasOfCard activeCard
