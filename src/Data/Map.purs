-- | This module defines a type of maps as balanced 2-3 trees, based on
-- | <http://www.cs.princeton.edu/~dpw/courses/cos326-12/ass/2-3-trees.pdf>

module Data.Map
  ( Map
  , showTree
  , empty
  , isEmpty
  , singleton
  , checkValid
  , insert
  , lookup
  , lookupLE
  , lookupLT
  , lookupGE
  , lookupGT
  , findMin
  , findMax
  , foldSubmap
  , submap
  , fromFoldable
  , fromFoldableWith
  , toUnfoldable
  , toAscUnfoldable
  , delete
  , pop
  , member
  , alter
  , update
  , keys
  , values
  , union
  , unionWith
  , unions
  , isSubmap
  , size
  , mapWithKey
  , filterWithKey
  , filterKeys
  , filter
  ) where

import Prelude

import Data.Eq (class Eq1)
import Data.Foldable (foldl, foldMap, foldr, class Foldable)
import Data.FoldableWithIndex (class FoldableWithIndex)
import Data.FunctorWithIndex (class FunctorWithIndex, mapWithIndex)
import Data.List (List(..), (:), length, nub)
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..), maybe, isJust, fromMaybe)
import Data.Ord (class Ord1)
import Data.Traversable (traverse, class Traversable)
import Data.TraversableWithIndex (class TraversableWithIndex, traverseWithIndex)
import Data.Tuple (Tuple(Tuple), snd, uncurry)
import Data.Unfoldable (class Unfoldable, unfoldr)
import Partial.Unsafe (unsafePartial)

-- | `Map k v` represents maps from keys of type `k` to values of type `v`.
data Map k v
  = Leaf
  | Two (Map k v) k v (Map k v)
  | Three (Map k v) k v (Map k v) k v (Map k v)

-- Internal use
toAscArray :: forall k v. Map k v -> Array (Tuple k v)
toAscArray = toAscUnfoldable

instance eq1Map :: Eq k => Eq1 (Map k) where
  eq1 = eq

instance eqMap :: (Eq k, Eq v) => Eq (Map k v) where
  eq m1 m2 = toAscArray m1 == toAscArray m2

instance ord1Map :: Ord k => Ord1 (Map k) where
  compare1 = compare

instance ordMap :: (Ord k, Ord v) => Ord (Map k v) where
  compare m1 m2 = compare (toAscArray m1) (toAscArray m2)

instance showMap :: (Show k, Show v) => Show (Map k v) where
  show m = "(fromFoldable " <> show (toAscArray m) <> ")"

instance semigroupMap :: Ord k => Semigroup (Map k v) where
  append = union

instance monoidMap :: Ord k => Monoid (Map k v) where
  mempty = empty

instance functorMap :: Functor (Map k) where
  map _ Leaf = Leaf
  map f (Two left k v right) = Two (map f left) k (f v) (map f right)
  map f (Three left k1 v1 mid k2 v2 right) = Three (map f left) k1 (f v1) (map f mid) k2 (f v2) (map f right)

instance functorWithIndexMap :: FunctorWithIndex k (Map k) where
  mapWithIndex _ Leaf = Leaf
  mapWithIndex f (Two left k v right) = Two (mapWithIndex f left) k (f k v) (mapWithIndex f right)
  mapWithIndex f (Three left k1 v1 mid k2 v2 right) = Three (mapWithIndex f left) k1 (f k1 v1) (mapWithIndex f mid) k2 (f k2 v2) (mapWithIndex f right)

instance foldableMap :: Foldable (Map k) where
  foldl   f z m = foldl   f z (values m)
  foldr   f z m = foldr   f z (values m)
  foldMap f   m = foldMap f   (values m)

instance foldableWithIndexMap :: FoldableWithIndex k (Map k) where
  foldlWithIndex f z m = foldl (uncurry <<< (flip f)) z $ asList $ toUnfoldable m
  foldrWithIndex f z m = foldr (uncurry f) z $ asList $ toUnfoldable m
  foldMapWithIndex f m = foldMap (uncurry f) $ asList $ toUnfoldable m

asList :: forall k v. List (Tuple k v) -> List (Tuple k v)
asList = identity

instance traversableMap :: Traversable (Map k) where
  traverse f Leaf = pure Leaf
  traverse f (Two left k v right) =
    Two <$> traverse f left
        <*> pure k
        <*> f v
        <*> traverse f right
  traverse f (Three left k1 v1 mid k2 v2 right) =
    Three <$> traverse f left
          <*> pure k1
          <*> f v1
          <*> traverse f mid
          <*> pure k2
          <*> f v2
          <*> traverse f right
  sequence = traverse identity

instance traversableWithIndexMap :: TraversableWithIndex k (Map k) where
  traverseWithIndex f Leaf = pure Leaf
  traverseWithIndex f (Two left k v right) =
    Two <$> traverseWithIndex f left
        <*> pure k
        <*> f k v
        <*> traverseWithIndex f right
  traverseWithIndex f (Three left k1 v1 mid k2 v2 right) =
    Three <$> traverseWithIndex f left
          <*> pure k1
          <*> f k1 v1
          <*> traverseWithIndex f mid
          <*> pure k2
          <*> f k2 v2
          <*> traverseWithIndex f right

-- | Render a `Map` as a `String`
showTree :: forall k v. Show k => Show v => Map k v -> String
showTree Leaf = "Leaf"
showTree (Two left k v right) =
  "Two (" <> showTree left <>
  ") (" <> show k <>
  ") (" <> show v <>
  ") (" <> showTree right <> ")"
showTree (Three left k1 v1 mid k2 v2 right) =
  "Three (" <> showTree left <>
  ") (" <> show k1 <>
  ") (" <> show v1 <>
  ") (" <> showTree mid <>
  ") (" <> show k2 <>
  ") (" <> show v2 <>
  ") (" <> showTree right <> ")"

-- | An empty map
empty :: forall k v. Map k v
empty = Leaf

-- | Test if a map is empty
isEmpty :: forall k v. Map k v -> Boolean
isEmpty Leaf = true
isEmpty _ = false

-- | Create a map with one key/value pair
singleton :: forall k v. k -> v -> Map k v
singleton k v = Two Leaf k v Leaf

-- | Check whether the underlying tree satisfies the 2-3 invariant
-- |
-- | This function is provided for internal use.
checkValid :: forall k v. Map k v -> Boolean
checkValid tree = length (nub (allHeights tree)) == one
  where
  allHeights :: Map k v -> List Int
  allHeights Leaf = pure zero
  allHeights (Two left _ _ right) = map (\n -> n + one) (allHeights left <> allHeights right)
  allHeights (Three left _ _ mid _ _ right) = map (\n -> n + one) (allHeights left <> allHeights mid <> allHeights right)

-- | Look up a value for the specified key
lookup :: forall k v. Ord k => k -> Map k v -> Maybe v
lookup k = go
  where
    comp :: k -> k -> Ordering
    comp = compare

    go Leaf = Nothing
    go (Two left k1 v right) =
      case comp k k1 of
        EQ -> Just v
        LT -> go left
        _  -> go right
    go (Three left k1 v1 mid k2 v2 right) =
      case comp k k1 of
        EQ -> Just v1
        c1 ->
          case c1, comp k k2 of
            _ , EQ -> Just v2
            LT, _  -> go left
            _ , GT -> go right
            _ , _  -> go mid


-- | Look up a value for the specified key, or the greatest one less than it
lookupLE :: forall k v. Ord k => k -> Map k v -> Maybe { key :: k, value :: v }
lookupLE k = go
  where
    comp :: k -> k -> Ordering
    comp = compare

    go Leaf = Nothing
    go (Two left k1 v1 right) = case comp k k1 of
      EQ -> Just { key: k1, value: v1 }
      GT -> Just $ fromMaybe { key: k1, value: v1 } $ go right
      LT -> go left
    go (Three left k1 v1 mid k2 v2 right) = case comp k k2 of
      EQ -> Just { key: k2, value: v2 }
      GT -> Just $ fromMaybe { key: k2, value: v2 } $ go right
      LT -> go $ Two left k1 v1 mid

-- | Look up a value for the greatest key less than the specified key
lookupLT :: forall k v. Ord k => k -> Map k v -> Maybe { key :: k, value :: v }
lookupLT k = go
  where
    comp :: k -> k -> Ordering
    comp = compare

    go Leaf = Nothing
    go (Two left k1 v1 right) = case comp k k1 of
      EQ -> findMax left
      GT -> Just $ fromMaybe { key: k1, value: v1 } $ go right
      LT -> go left
    go (Three left k1 v1 mid k2 v2 right) = case comp k k2 of
      EQ -> findMax $ Two left k1 v1 mid
      GT -> Just $ fromMaybe { key: k2, value: v2 } $ go right
      LT -> go $ Two left k1 v1 mid

-- | Look up a value for the specified key, or the least one greater than it
lookupGE :: forall k v. Ord k => k -> Map k v -> Maybe { key :: k, value :: v }
lookupGE k = go
  where
    comp :: k -> k -> Ordering
    comp = compare

    go Leaf = Nothing
    go (Two left k1 v1 right) = case comp k k1 of
      EQ -> Just { key: k1, value: v1 }
      LT -> Just $ fromMaybe { key: k1, value: v1 } $ go left
      GT -> go right
    go (Three left k1 v1 mid k2 v2 right) = case comp k k1 of
      EQ -> Just { key: k1, value: v1 }
      LT -> Just $ fromMaybe { key: k1, value: v1 } $ go left
      GT -> go $ Two mid k2 v2 right

-- | Look up a value for the least key greater than the specified key
lookupGT :: forall k v. Ord k => k -> Map k v -> Maybe { key :: k, value :: v }
lookupGT k = go
  where
    comp :: k -> k -> Ordering
    comp = compare

    go Leaf = Nothing
    go (Two left k1 v1 right) = case comp k k1 of
      EQ -> findMin right
      LT -> Just $ fromMaybe { key: k1, value: v1 } $ go left
      GT -> go right
    go (Three left k1 v1 mid k2 v2 right) = case comp k k1 of
      EQ -> findMin $ Two mid k2 v2 right
      LT -> Just $ fromMaybe { key: k1, value: v1 } $ go left
      GT -> go $ Two mid k2 v2 right

-- | Returns the pair with the greatest key
findMax :: forall k v. Map k v -> Maybe { key :: k, value :: v }
findMax = go Nothing
  where
    go acc Leaf = acc
    go _   (Two _ k1 v1 right) = go (Just { key: k1, value: v1 }) right
    go _   (Three _ _ _ _ k2 v2 right) = go (Just { key: k2, value: v2 }) right

-- | Returns the pair with the least key
findMin :: forall k v. Map k v -> Maybe { key :: k, value :: v }
findMin = go Nothing
  where
    go acc Leaf = acc
    go _   (Two left k1 v1 _) = go (Just { key: k1, value: v1 }) left
    go _   (Three left k1 v1 _ _ _ _) = go (Just { key: k1, value: v1 }) left

-- | Fold over the entries of a given map where the key is between a lower and
-- | an upper bound. Passing `Nothing` as either the lower or upper bound
-- | argument means that the fold has no lower or upper bound, i.e. the fold
-- | starts from (or ends with) the smallest (or largest) key in the map.
-- |
-- | ```purescript
-- | foldSubmap (Just 1) (Just 2) (\_ v -> [v])
-- |  (fromFoldable [Tuple 0 "zero", Tuple 1 "one", Tuple 2 "two", Tuple 3 "three"])
-- |  == ["one", "two"]
-- |
-- | foldSubmap Nothing (Just 2) (\_ v -> [v])
-- |  (fromFoldable [Tuple 0 "zero", Tuple 1 "one", Tuple 2 "two", Tuple 3 "three"])
-- |  == ["zero", "one", "two"]
-- | ```
foldSubmap :: forall k v m. Ord k => Monoid m => Maybe k -> Maybe k -> (k -> v -> m) -> Map k v -> m
foldSubmap kmin kmax f =
  let
    tooSmall =
      case kmin of
        Just kmin' ->
          \k -> k < kmin'
        Nothing ->
          const false

    tooLarge =
      case kmax of
        Just kmax' ->
          \k -> k > kmax'
        Nothing ->
          const false

    inBounds =
      case kmin, kmax of
        Just kmin', Just kmax' ->
          \k -> kmin' <= k && k <= kmax'
        Just kmin', Nothing ->
          \k -> kmin' <= k
        Nothing, Just kmax' ->
          \k -> k <= kmax'
        Nothing, Nothing ->
          const true

    -- We can take advantage of the invariants of the tree structure to reduce
    -- the amount of work we need to do. For example, in the following tree:
    --
    --      [2][4]
    --      / |  \
    --     /  |   \
    --   [1] [3] [5]
    --
    -- If we are given a lower bound of 3, we do not need to inspect the left
    -- subtree, because we know that every entry in it is less than or equal to
    -- 2. Similarly, if we are given a lower bound of 5, we do not need to
    -- inspect the central subtree, because we know that every entry in it must
    -- be less than or equal to 4.
    --
    -- Unfortunately we cannot extract `if cond then x else mempty` into a
    -- function because of strictness.
    go = case _ of
      Leaf ->
        mempty
      Two left k v right ->
           (if tooSmall k then mempty else go left)
        <> (if inBounds k then f k v else mempty)
        <> (if tooLarge k then mempty else go right)
      Three left k1 v1 mid k2 v2 right ->
           (if tooSmall k1 then mempty else go left)
        <> (if inBounds k1 then f k1 v1 else mempty)
        <> (if tooSmall k2 || tooLarge k1 then mempty else go mid)
        <> (if inBounds k2 then f k2 v2 else mempty)
        <> (if tooLarge k2 then mempty else go right)
  in
    go

-- | Returns a new map containing all entries of the given map which lie
-- | between a given lower and upper bound, treating `Nothing` as no bound i.e.
-- | including the smallest (or largest) key in the map, no matter how small
-- | (or large) it is. For example:
-- |
-- | ```purescript
-- | submap (Just 1) (Just 2)
-- |   (fromFoldable [Tuple 0 "zero", Tuple 1 "one", Tuple 2 "two", Tuple 3 "three"])
-- |   == fromFoldable [Tuple 1 "one", Tuple 2 "two"]
-- |
-- | submap Nothing (Just 2)
-- |   (fromFoldable [Tuple 0 "zero", Tuple 1 "one", Tuple 2 "two", Tuple 3 "three"])
-- |   == fromFoldable [Tuple 0 "zero", Tuple 1 "one", Tuple 2 "two"]
-- | ```
-- |
-- | The function is entirely specified by the following
-- | property:
-- |
-- | ```purescript
-- | Given any m :: Map k v, mmin :: Maybe k, mmax :: Maybe k, key :: k,
-- |   let m' = submap mmin mmax m in
-- |     if (maybe true (\min -> min <= key) mmin &&
-- |         maybe true (\max -> max >= key) mmax)
-- |       then lookup key m == lookup key m'
-- |       else not (member key m')
-- | ```
submap :: forall k v. Ord k => Maybe k -> Maybe k -> Map k v -> Map k v
submap kmin kmax = foldSubmap kmin kmax singleton

-- | Test if a key is a member of a map
member :: forall k v. Ord k => k -> Map k v -> Boolean
member k m = isJust (k `lookup` m)

data TreeContext k v
  = TwoLeft k v (Map k v)
  | TwoRight (Map k v) k v
  | ThreeLeft k v (Map k v) k v (Map k v)
  | ThreeMiddle (Map k v) k v k v (Map k v)
  | ThreeRight (Map k v) k v (Map k v) k v

fromZipper :: forall k v. Ord k => List (TreeContext k v) -> Map k v -> Map k v
fromZipper Nil tree = tree
fromZipper (Cons x ctx) tree =
  case x of
    TwoLeft k1 v1 right -> fromZipper ctx (Two tree k1 v1 right)
    TwoRight left k1 v1 -> fromZipper ctx (Two left k1 v1 tree)
    ThreeLeft k1 v1 mid k2 v2 right -> fromZipper ctx (Three tree k1 v1 mid k2 v2 right)
    ThreeMiddle left k1 v1 k2 v2 right -> fromZipper ctx (Three left k1 v1 tree k2 v2 right)
    ThreeRight left k1 v1 mid k2 v2 -> fromZipper ctx (Three left k1 v1 mid k2 v2 tree)

data KickUp k v = KickUp (Map k v) k v (Map k v)

-- | Insert or replace a key/value pair in a map
insert :: forall k v. Ord k => k -> v -> Map k v -> Map k v
insert k v = down Nil
  where
  comp :: k -> k -> Ordering
  comp = compare

  down :: List (TreeContext k v) -> Map k v -> Map k v
  down ctx Leaf = up ctx (KickUp Leaf k v Leaf)
  down ctx (Two left k1 v1 right) =
    case comp k k1 of
      EQ -> fromZipper ctx (Two left k v right)
      LT -> down (Cons (TwoLeft k1 v1 right) ctx) left
      _  -> down (Cons (TwoRight left k1 v1) ctx) right
  down ctx (Three left k1 v1 mid k2 v2 right) =
    case comp k k1 of
      EQ -> fromZipper ctx (Three left k v mid k2 v2 right)
      c1 ->
        case c1, comp k k2 of
          _ , EQ -> fromZipper ctx (Three left k1 v1 mid k v right)
          LT, _  -> down (Cons (ThreeLeft k1 v1 mid k2 v2 right) ctx) left
          GT, LT -> down (Cons (ThreeMiddle left k1 v1 k2 v2 right) ctx) mid
          _ , _  -> down (Cons (ThreeRight left k1 v1 mid k2 v2) ctx) right

  up :: List (TreeContext k v) -> KickUp k v -> Map k v
  up Nil (KickUp left k' v' right) = Two left k' v' right
  up (Cons x ctx) kup =
    case x, kup of
      TwoLeft k1 v1 right, KickUp left k' v' mid -> fromZipper ctx (Three left k' v' mid k1 v1 right)
      TwoRight left k1 v1, KickUp mid k' v' right -> fromZipper ctx (Three left k1 v1 mid k' v' right)
      ThreeLeft k1 v1 c k2 v2 d, KickUp a k' v' b -> up ctx (KickUp (Two a k' v' b) k1 v1 (Two c k2 v2 d))
      ThreeMiddle a k1 v1 k2 v2 d, KickUp b k' v' c -> up ctx (KickUp (Two a k1 v1 b) k' v' (Two c k2 v2 d))
      ThreeRight a k1 v1 b k2 v2, KickUp c k' v' d -> up ctx (KickUp (Two a k1 v1 b) k2 v2 (Two c k' v' d))

-- | Delete a key and its corresponding value from a map.
delete :: forall k v. Ord k => k -> Map k v -> Map k v
delete k m = maybe m snd (pop k m)

-- | Delete a key and its corresponding value from a map, returning the value
-- | as well as the subsequent map.
pop :: forall k v. Ord k => k -> Map k v -> Maybe (Tuple v (Map k v))
pop k = down Nil
  where
  comp :: k -> k -> Ordering
  comp = compare

  down :: List (TreeContext k v) -> Map k v -> Maybe (Tuple v (Map k v))
  down = unsafePartial \ctx m -> case m of
    Leaf -> Nothing
    Two left k1 v1 right ->
      case right, comp k k1 of
        Leaf, EQ -> Just (Tuple v1 (up ctx Leaf))
        _   , EQ -> let max = maxNode left
                     in Just (Tuple v1 (removeMaxNode (Cons (TwoLeft max.key max.value right) ctx) left))
        _   , LT -> down (Cons (TwoLeft k1 v1 right) ctx) left
        _   , _  -> down (Cons (TwoRight left k1 v1) ctx) right
    Three left k1 v1 mid k2 v2 right ->
      let leaves =
            case left, mid, right of
              Leaf, Leaf, Leaf -> true
              _   , _   , _    -> false
      in case leaves, comp k k1, comp k k2 of
        true, EQ, _  -> Just (Tuple v1 (fromZipper ctx (Two Leaf k2 v2 Leaf)))
        true, _ , EQ -> Just (Tuple v2 (fromZipper ctx (Two Leaf k1 v1 Leaf)))
        _   , EQ, _  -> let max = maxNode left
                         in Just (Tuple v1 (removeMaxNode (Cons (ThreeLeft max.key max.value mid k2 v2 right) ctx) left))
        _   , _ , EQ -> let max = maxNode mid
                         in Just (Tuple v2 (removeMaxNode (Cons (ThreeMiddle left k1 v1 max.key max.value right) ctx) mid))
        _   , LT, _  -> down (Cons (ThreeLeft k1 v1 mid k2 v2 right) ctx) left
        _   , GT, LT -> down (Cons (ThreeMiddle left k1 v1 k2 v2 right) ctx) mid
        _   , _ , _  -> down (Cons (ThreeRight left k1 v1 mid k2 v2) ctx) right

  up :: List (TreeContext k v) -> Map k v -> Map k v
  up = unsafePartial \ctxs tree ->
    case ctxs of
      Nil -> tree
      Cons x ctx ->
        case x, tree of
          TwoLeft k1 v1 Leaf, Leaf -> fromZipper ctx (Two Leaf k1 v1 Leaf)
          TwoRight Leaf k1 v1, Leaf -> fromZipper ctx (Two Leaf k1 v1 Leaf)
          TwoLeft k1 v1 (Two m k2 v2 r), l -> up ctx (Three l k1 v1 m k2 v2 r)
          TwoRight (Two l k1 v1 m) k2 v2, r -> up ctx (Three l k1 v1 m k2 v2 r)
          TwoLeft k1 v1 (Three b k2 v2 c k3 v3 d), a -> fromZipper ctx (Two (Two a k1 v1 b) k2 v2 (Two c k3 v3 d))
          TwoRight (Three a k1 v1 b k2 v2 c) k3 v3, d -> fromZipper ctx (Two (Two a k1 v1 b) k2 v2 (Two c k3 v3 d))
          ThreeLeft k1 v1 Leaf k2 v2 Leaf, Leaf -> fromZipper ctx (Three Leaf k1 v1 Leaf k2 v2 Leaf)
          ThreeMiddle Leaf k1 v1 k2 v2 Leaf, Leaf -> fromZipper ctx (Three Leaf k1 v1 Leaf k2 v2 Leaf)
          ThreeRight Leaf k1 v1 Leaf k2 v2, Leaf -> fromZipper ctx (Three Leaf k1 v1 Leaf k2 v2 Leaf)
          ThreeLeft k1 v1 (Two b k2 v2 c) k3 v3 d, a -> fromZipper ctx (Two (Three a k1 v1 b k2 v2 c) k3 v3 d)
          ThreeMiddle (Two a k1 v1 b) k2 v2 k3 v3 d, c -> fromZipper ctx (Two (Three a k1 v1 b k2 v2 c) k3 v3 d)
          ThreeMiddle a k1 v1 k2 v2 (Two c k3 v3 d), b -> fromZipper ctx (Two a k1 v1 (Three b k2 v2 c k3 v3 d))
          ThreeRight a k1 v1 (Two b k2 v2 c) k3 v3, d -> fromZipper ctx (Two a k1 v1 (Three b k2 v2 c k3 v3 d))
          ThreeLeft k1 v1 (Three b k2 v2 c k3 v3 d) k4 v4 e, a -> fromZipper ctx (Three (Two a k1 v1 b) k2 v2 (Two c k3 v3 d) k4 v4 e)
          ThreeMiddle (Three a k1 v1 b k2 v2 c) k3 v3 k4 v4 e, d -> fromZipper ctx (Three (Two a k1 v1 b) k2 v2 (Two c k3 v3 d) k4 v4 e)
          ThreeMiddle a k1 v1 k2 v2 (Three c k3 v3 d k4 v4 e), b -> fromZipper ctx (Three a k1 v1 (Two b k2 v2 c) k3 v3 (Two d k4 v4 e))
          ThreeRight a k1 v1 (Three b k2 v2 c k3 v3 d) k4 v4, e -> fromZipper ctx (Three a k1 v1 (Two b k2 v2 c) k3 v3 (Two d k4 v4 e))

  maxNode :: Map k v -> { key :: k, value :: v }
  maxNode = unsafePartial \m -> case m of
    Two _ k' v Leaf -> { key: k', value: v }
    Two _ _ _ right -> maxNode right
    Three _ _ _ _ k' v Leaf -> { key: k', value: v }
    Three _ _ _ _ _ _ right -> maxNode right


  removeMaxNode :: List (TreeContext k v) -> Map k v -> Map k v
  removeMaxNode = unsafePartial \ctx m ->
    case m of
      Two Leaf _ _ Leaf -> up ctx Leaf
      Two left k' v right -> removeMaxNode (Cons (TwoRight left k' v) ctx) right
      Three Leaf k1 v1 Leaf _ _ Leaf -> up (Cons (TwoRight Leaf k1 v1) ctx) Leaf
      Three left k1 v1 mid k2 v2 right -> removeMaxNode (Cons (ThreeRight left k1 v1 mid k2 v2) ctx) right


-- | Insert the value, delete a value, or update a value for a key in a map
alter :: forall k v. Ord k => (Maybe v -> Maybe v) -> k -> Map k v -> Map k v
alter f k m = case f (k `lookup` m) of
  Nothing -> delete k m
  Just v -> insert k v m

-- | Update or delete the value for a key in a map
update :: forall k v. Ord k => (v -> Maybe v) -> k -> Map k v -> Map k v
update f k m = alter (maybe Nothing f) k m

-- | Convert any foldable collection of key/value pairs to a map.
-- | On key collision, later values take precedence over earlier ones.
fromFoldable :: forall f k v. Ord k => Foldable f => f (Tuple k v) -> Map k v
fromFoldable = foldl (\m (Tuple k v) -> insert k v m) empty

-- | Convert any foldable collection of key/value pairs to a map.
-- | On key collision, the values are configurably combined.
fromFoldableWith :: forall f k v. Ord k => Foldable f => (v -> v -> v) -> f (Tuple k v) -> Map k v
fromFoldableWith f = foldl (\m (Tuple k v) -> alter (combine v) k m) empty where
  combine v (Just v') = Just $ f v v'
  combine v Nothing = Just v

-- | Convert a map to an unfoldable structure of key/value pairs
toUnfoldable :: forall f k v. Unfoldable f => Map k v -> f (Tuple k v)
toUnfoldable m = unfoldr go (m : Nil) where
  go Nil = Nothing
  go (hd : tl) = case hd of
    Leaf -> go tl
    Two left k v right ->
      Just $ Tuple (Tuple k v) (left : right : tl)
    Three left k1 v1 mid k2 v2 right ->
      Just $ Tuple (Tuple k1 v1) (singleton k2 v2 : left : mid : right : tl)

-- | Convert a map to an unfoldable structure of key/value pairs where the keys are in ascending order
toAscUnfoldable :: forall f k v. Unfoldable f => Map k v -> f (Tuple k v)
toAscUnfoldable m = unfoldr go (m : Nil) where
  go Nil = Nothing
  go (hd : tl) = case hd of
    Leaf -> go tl
    Two Leaf k v Leaf ->
      Just $ Tuple (Tuple k v) tl
    Two Leaf k v right ->
      Just $ Tuple (Tuple k v) (right : tl)
    Two left k v right ->
      go $ left : singleton k v : right : tl
    Three left k1 v1 mid k2 v2 right ->
      go $ left : singleton k1 v1 : mid : singleton k2 v2 : right : tl

-- | Get a list of the keys contained in a map
keys :: forall k v. Map k v -> List k
keys Leaf = Nil
keys (Two left k _ right) = keys left <> pure k <> keys right
keys (Three left k1 _ mid k2 _ right) = keys left <> pure k1 <> keys mid <> pure k2 <> keys right

-- | Get a list of the values contained in a map
values :: forall k v. Map k v -> List v
values Leaf = Nil
values (Two left _ v right) = values left <> pure v <> values right
values (Three left _ v1 mid _ v2 right) = values left <> pure v1 <> values mid <> pure v2 <> values right

-- | Compute the union of two maps, using the specified function
-- | to combine values for duplicate keys.
unionWith :: forall k v. Ord k => (v -> v -> v) -> Map k v -> Map k v -> Map k v
unionWith f m1 m2 = foldl go m2 (toUnfoldable m1 :: List (Tuple k v))
  where
  go m (Tuple k v) = alter (Just <<< maybe v (f v)) k m

-- | Compute the union of two maps, preferring values from the first map in the case
-- | of duplicate keys
union :: forall k v. Ord k => Map k v -> Map k v -> Map k v
union = unionWith const

-- | Compute the union of a collection of maps
unions :: forall k v f. Ord k => Foldable f => f (Map k v) -> Map k v
unions = foldl union empty

-- | Test whether one map contains all of the keys and values contained in another map
isSubmap :: forall k v. Ord k => Eq v => Map k v -> Map k v -> Boolean
isSubmap m1 m2 = LL.all f $ (toUnfoldable m1 :: LL.List (Tuple k v))
  where f (Tuple k v) = lookup k m2 == Just v

-- | Calculate the number of key/value pairs in a map
size :: forall k v. Map k v -> Int
size Leaf = 0
size (Two m1 _ _ m2) = 1 + size m1 + size m2
size (Three m1 _ _ m2 _ _ m3) = 2 + size m1 + size m2 + size m3

-- | Apply a function of two arguments to each key/value pair, producing a new map
mapWithKey :: forall k v v'. (k -> v -> v') -> Map k v -> Map k v'
mapWithKey _ Leaf = Leaf
mapWithKey f (Two left k v right) = Two (mapWithKey f left) k (f k v) (mapWithKey f right)
mapWithKey f (Three left k1 v1 mid k2 v2 right) = Three (mapWithKey f left) k1 (f k1 v1) (mapWithKey f mid) k2 (f k2 v2) (mapWithKey f right)

-- | Filter out those key/value pairs of a map for which a predicate
-- | fails to hold.
filterWithKey :: forall k v. Ord k => (k -> v -> Boolean) -> Map k v -> Map k v
filterWithKey predicate =
  fromFoldable <<< LL.filter (uncurry predicate) <<< toUnfoldable

-- | Filter out those key/value pairs of a map for which a predicate
-- | on the key fails to hold.
filterKeys :: forall k. Ord k => (k -> Boolean) -> Map k ~> Map k
filterKeys predicate = filterWithKey $ const <<< predicate

-- | Filter out those key/value pairs of a map for which a predicate
-- | on the value fails to hold.
filter :: forall k v. Ord k => (v -> Boolean) -> Map k v -> Map k v
filter predicate = filterWithKey $ const predicate
