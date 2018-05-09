{- Haskell98! -}

{-# LANGUAGE CPP #-}

-- $HeadURL: https://svn.metnet.navy.mil/svn/metcast/Mserver/trunk/soutei/haskell/Soutei/FBackTrackT.hs $
-- $Id: FBackTrackT.hs 2926 2012-09-07 04:43:30Z oleg.kiselyov $
-- svn propset svn:keywords "HeadURL Id" filename

-- Simple Fair back-tracking monad TRANSFORMER
-- Made by `transforming' the stand-alone monad from FBackTrack.hs,
-- which, in turn, is based on the Scheme code book-si, 
-- `Stream implementation, with incomplete' as of Feb 18, 2005
--
-- The transformatiion from a stand-alone Stream monad to a monad transformer
-- is not at all similar to the trick described in Ralf Hinze's ICFP'00 paper,
-- Deriving backtracking monad transformers. 

-- $Id: FBackTrackT.hs 2926 2012-09-07 04:43:30Z oleg.kiselyov $

module Soutei.FBackTrackT (Stream, yield, runM) where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans
import Control.Monad.Identity

data StreamE m a = Nil | One a | 
		   Choice a (Stream m a) | 
		   Incomplete (Stream m a)

instance Functor m => Functor (StreamE m) where
  fmap _ Nil = Nil
  fmap f (One a) = One (f a)
  fmap f (Choice a as) = Choice (f a) (fmap f as)
  fmap f (Incomplete as) = Incomplete (fmap f as)

newtype Stream m a = Stream {unStream :: m (StreamE m a)}

instance Functor m => Functor (Stream m) where
  fmap f (Stream as) = Stream (fmap (fmap f) as)

#if __GLASGOW_HASKELL__ < 710 
instance (Functor m, Monad m) => Applicative (Stream m) where
#else
instance Monad m => Applicative (Stream m) where
#endif
  pure = Stream . return . One
  (<*>) = ap

instance Monad m => Monad (Stream m) where
  return = Stream . return . One

  m >>= f = Stream (unStream m >>= bind)
    where
    bind Nil            = return Nil
    bind (One a)        = unStream $ f a
    bind (Choice a r)   = unStream $ f a `mplus` (yield (r >>= f))
    bind (Incomplete i) = return $ Incomplete (i >>= f)

yield :: Monad m => Stream m a -> Stream m a
yield = Stream . return . Incomplete

#if __GLASGOW_HASKELL__ < 710 
instance (Functor m, Monad m) => Alternative (Stream m) where
#else
instance Monad m => Alternative (Stream m) where
#endif
  empty = mzero
  (<|>) = mplus

instance Monad m => MonadPlus (Stream m) where
  mzero = Stream $ return Nil

  mplus m1 m2 = Stream (unStream m1 >>= mplus')
   where
   mplus' Nil          = return $ Incomplete m2
   mplus' (One a)      = return $ Choice a m2
   mplus' (Choice a r) = return $ Choice a (mplus m2 r) -- interleaving!
   --mplus' (Incomplete i) = return $ Incomplete (mplus i m2)
   mplus' r@(Incomplete i) = unStream m2 >>= \r' ->
      case r' of
	      Nil         -> return r
	      One b       -> return $ Choice b i
	      Choice b r' -> return $ Choice b (mplus i r')
	      -- Choice _ _ -> Incomplete (mplus r' i)
	      Incomplete j -> return $ Incomplete $ Stream $ return $ Incomplete (mplus i j)


instance MonadTrans Stream where
    lift m = Stream (m >>= return . One)

instance MonadIO m => MonadIO (Stream m) where
    liftIO = lift . liftIO


-- run the Monad, to a specific depth, and give at most
-- specified number of answers. The monad `m' may be strict (like IO),
-- so we can't count on the laziness of the `[a]'
runM :: Monad m => Maybe Int -> Maybe Int -> Stream m a -> m [a]
runM _ (Just 0)  _  = return []			-- out of breadth
runM d b         m  = unStream m >>= runM' d b
runM' _ _   Nil   = return []
runM' _ _ (One a) = return [a]
runM' d b (Choice a r) = do t <- runM d (liftM pred b) r; return (a:t)
runM' (Just 0) _ (Incomplete r) = return []	-- exhausted depth
runM' d b (Incomplete r) = runM (liftM pred d) b r


-- Don't try the following with the regular List monad or List comprehension!
-- That would diverge instantly: all `i', `j', and `k' are infinite
-- streams

pythagorean_triples :: MonadPlus m => m (Int,Int,Int)
pythagorean_triples =
    let number = (return 0) `mplus` (number >>= return . succ) in
    do
    i <- number
    guard $ i > 0
    j <- number
    guard $ j > 0
    k <- number
    guard $ k > 0
    guard $ i*i + j*j == k*k
    return (i,j,k)

-- If you run this in GHCi, you can see that Indetity is a lazy monad 
-- and IO is strict: evaluating `test' prints the answers as they are computed.
-- OTH, testio runs silently for a while and then prints all the answers
-- at once
test = runIdentity $ runM Nothing (Just 7) pythagorean_triples
testio = runM Nothing (Just 7) pythagorean_triples >>= print


-- The following code is not in general MonadPlus: it uses Incomplete
-- explicitly. But it supports left recursion! Note that in OCaml, for example,
-- we _must_ include that Incomplete data constructor to make
-- the recursive definition well-formed.  
-- The code does *not* get stuck in the generation of primitive tuples
-- like (0,1,1), (0,2,2), (0,3,3) etc.
pythagorean_triples' :: Monad m => Stream m (Int,Int,Int)
pythagorean_triples' =
    let number = (yield number >>= return . succ) `mplus` return 0  in
    do
    i <- number
    j <- number
    k <- number
    guard $ i*i + j*j == k*k
    return (i,j,k)

test'   = runIdentity $ runM Nothing (Just 27) pythagorean_triples'
testio' = runM Nothing (Just 27) pythagorean_triples' >>= print

pythagorean_triples'' :: Stream IO (Int,Int,Int)
pythagorean_triples'' =
    let number = (yield number >>= return . succ) `mplus` return 0  in
    do
    i <- number
    j <- number
    k <- number
    liftIO $ print (i,j,k)
    guard $ i*i + j*j == k*k
    return (i,j,k)

testio'' = runM Nothing (Just 7) pythagorean_triples'' >>= print

-- a serious test of left recursion (due to Will Byrd)
flaz x = yield (flaz x) `mplus` (yield (flaz x) `mplus`
				      if x == 5 then return x else mzero)
test_flaz = runIdentity $ runM Nothing (Just 15) (flaz 5)
