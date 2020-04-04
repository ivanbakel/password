{-# LANGUAGE ExplicitForAll #-}
{-|
Module      : Data.Password.Bcrypt
Copyright   : (c) Felix Paulusma, 2020
License     : BSD-style (see LICENSE file)
Maintainer  : cdep.illabout@gmail.com
Stability   : experimental
Portability : POSIX

= bcrypt

The @bcrypt@ algorithm is a popular way of hashing passwords.
It is based on the Blowfish cipher and fairly straightfoward
in its usage. It has a cost parameter that, when increased,
slows down the hashing speed.

It is a straightforward and easy way to get decent protection
on passwords, it is also been around long enough to be battle-tested
and generally considered to provide a good amount of security.

== Other algorithms

@bcrypt@, together with @PBKDF2@, are only computationally intensive.
And to protect from specialized hardware, new algorithms have been
developed that are also resource intensive, like @scrypt@ and @Argon2@.
Not having high resource demands, means an attacker with specialized
software could take less time to brute-force a password, though with
the default cost (12) and a decently long password, the amount of
time to brute-force would still be significant.
-}

-- I think the portability is broadened to
-- whatever, now that we use cryptonite... I think
module Data.Password.Bcrypt (
  -- * Algorithm
  Bcrypt
  -- * Plain-text Password
  , Pass
  , mkPass
  -- * Hash Passwords (bcrypt)
  , hashPass
  , PassHash(..)
  -- * Verify Passwords (bcrypt)
  , checkPass
  , PassCheck(..)
  -- * Hashing Manually (bcrypt)
  --
  -- | If you have any doubt about what the cost does or means,
  -- please just use 'hashPass'.
  , hashPassWithParams
  -- ** Hashing with salt (DISADVISED)
  --
  -- | Hashing with a set 'Salt' is almost never what you want
  -- to do. Use 'hashPass' or 'hashPassWithParams' to have
  -- automatic generation of randomized salts.
  , hashPassWithSalt
  , Salt(..)
  , newSalt
  -- * Unsafe Debugging Functions for Showing a Password
  --
  -- | Use at your own risk
  , unsafeShowPassword
  , unsafeShowPasswordText
  , -- * Setup for doctests.
    -- $setup
  ) where

import Control.Monad.IO.Class (MonadIO(liftIO))
import Crypto.KDF.BCrypt as Bcrypt
import Data.ByteArray (Bytes, convert)

import Data.Password (
         PassCheck(..)
       , PassHash(..)
       , Salt(..)
       , mkPass
       , unsafeShowPassword
       , unsafeShowPasswordText
       )
import Data.Password.Internal (Pass(..), fromBytes, toBytes)
import qualified Data.Password.Internal (newSalt)


-- | Phantom type for __bcrypt__
--
-- @since 2.0.0.0
data Bcrypt

-- $setup
-- >>> :set -XFlexibleInstances
-- >>> :set -XOverloadedStrings
--
-- Import needed libraries.
--
-- >>> import Data.Password
-- >>> import Data.ByteString (pack)
-- >>> import Test.QuickCheck (Arbitrary(arbitrary), Blind(Blind), vector)
-- >>> import Test.QuickCheck.Instances.Text ()
--
-- >>> instance Arbitrary (Salt a) where arbitrary = Salt . pack <$> vector 16
-- >>> instance Arbitrary Pass where arbitrary = fmap Pass arbitrary
-- >>> instance Arbitrary (PassHash Bcrypt) where arbitrary = hashPassWithSalt 8 <$> arbitrary <*> arbitrary

-- | Hash the 'Pass' using the /bcrypt/ hash algorithm.
--
-- __N.B.__: @bcrypt@ has a limit of 72 bytes as input, so anything longer than that
-- will be cut off at the 72 byte point and thus any password that is 72 bytes
-- or longer will match as long as the first 72 bytes are the same.
--
-- >>> hashPass $ mkPass "foobar"
-- PassHash {unPassHash = "$2b$10$..."}
hashPass :: MonadIO m => Pass -> m (PassHash Bcrypt)
hashPass = hashPassWithParams 10

-- | Hash a password with the given cost and also with the given 'Salt'
-- instead of generating a random salt. Using 'hashPassWithSalt' is strongly __disadvised__,
-- and 'hashPassWithParams' should be used instead. /Never use a static salt/
-- /in production applications!/
--
-- __N.B.__: The salt HAS to be 16 bytes or this function will throw an error!
--
-- >>> let salt = Salt "abcdefghijklmnop"
-- >>> hashPassWithSalt 10 salt (mkPass "foobar")
-- PassHash {unPassHash = "$2b$10$WUHhXETkX0fnYkrqZU3ta.N8Utt4U77kW4RVbchzgvBvBBEEdCD/u"}
--
-- (Note that we use an explicit 'Salt' in the example above.  This is so that the
-- example is reproducible, but in general you should use 'hashPass'. 'hashPass'
-- (and 'hashPassWithParams') generates a new 'Salt' everytime it is called.)
hashPassWithSalt
  :: Int -- ^ The cost parameter. Should be between 4 and 31 (inclusive). Values which lie outside this range will be adjusted accordingly.
  -> Salt Bcrypt -- ^ The salt. MUST be 16 bytes in length or an error will be raised.
  -> Pass -- ^ The password to be hashed.
  -> PassHash Bcrypt -- ^ The bcrypt hash in standard format.
hashPassWithSalt cost (Salt salt) (Pass pass) =
    let hash = Bcrypt.bcrypt cost (convert salt :: Bytes) (toBytes pass)
    in PassHash $ fromBytes hash

-- | Hash a password using the /bcrypt/ algorithm with the given cost.
--
-- The higher the cost, the longer 'hashPass' and 'checkPass' will take to run,
-- thus increasing the security, but taking longer and taking up more resources.
-- The optimal cost for generic user logins would be one that would take between
-- 0.05 - 0.5 seconds to check on the machine that will run it.
--
-- __N.B.__: It is advised to use 'hashPass' if you're unsure about the
-- implications that changing the cost brings with it.
--
-- @since 2.0.0.0
hashPassWithParams
  :: MonadIO m
  => Int -- ^ The cost parameter. Should be between 4 and 31 (inclusive). Values which lie outside this range will be adjusted accordingly.
  -> Pass -- ^ The password to be hashed.
  -> m (PassHash Bcrypt) -- ^ The bcrypt hash in standard format.
hashPassWithParams cost pass = liftIO $ do
    salt <- newSalt
    return $ hashPassWithSalt cost salt pass

-- | Check a 'Pass' against a 'PassHash' 'Bcrypt'.
--
-- Returns 'PassCheckSuccess' on success.
--
-- >>> let pass = mkPass "foobar"
-- >>> passHash <- hashPass pass
-- >>> checkPass pass passHash
-- PassCheckSuccess
--
-- Returns 'PassCheckFail' if an incorrect 'Pass' or 'PassHash' 'Bcrypt' is used.
--
-- >>> let badpass = mkPass "incorrect-password"
-- >>> checkPass badpass passHash
-- PassCheckFail
--
-- This should always fail if an incorrect password is given.
--
-- prop> \(Blind badpass) -> let correctPassHash = hashPassWithSalt 8 salt "foobar" in checkPass badpass correctPassHash == PassCheckFail
checkPass :: Pass -> PassHash Bcrypt -> PassCheck
checkPass (Pass pass) (PassHash passHash) =
    if Bcrypt.validatePassword (toBytes pass) (toBytes passHash)
      then PassCheckSuccess
      else PassCheckFail

-- | Generate a random 16-byte @bcrypt@ salt
--
-- @since 2.0.0.0
newSalt :: MonadIO m => m (Salt Bcrypt)
newSalt = Data.Password.Internal.newSalt 16
