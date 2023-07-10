module Botan.Utility
( botanConstantTimeCompare
, botanScrubMem
, botanHexEncodeText
, botanHexDecodeText
, botanBase64EncodeText
, botanBase64DecodeText
) where

import Prelude

import Control.Monad

import Data.Bool

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString

import Data.Word

import System.IO
import System.IO.Unsafe

import Foreign.C.Types
import Foreign.ForeignPtr
import Foreign.Marshal.Alloc
import Foreign.Ptr

import Botan.Error
import Botan.Prelude

-- NOTE: I just discovered:
--  https://hackage.haskell.org/package/memory-0.18.0/docs/Data-ByteArray-Encoding.html
-- Where have you been all my life?

-- TODO: Discuss whether it is wise to remove the ccall IO constraint from
--  idempotent crypto functions in order to 'make them pure'.

-- | int botan_constant_time_compare(const uint8_t *x, const uint8_t *y, size_t len)
-- NOTE: Return type is CInt, not BotanErrorCode. Function is explicit about return values.
foreign import ccall unsafe botan_constant_time_compare :: Ptr Word8 -> Ptr Word8 -> CSize -> IO CInt

-- | Returns 0 if x[0..len] == y[0..len], -1 otherwise.
-- NOTE: Here for completeness, because Data.ByteArray.constEq already exists.
-- DISCUSS: Should this be used in favor of Data.ByteArray.constEq?
-- TODO: Expose explicit length? Compare up to length of shorter? Compare up to length of 1st? (Error if len first > second)
botanConstantTimeCompare :: ByteString -> ByteString -> Bool
botanConstantTimeCompare x y = if ByteString.length x == ByteString.length y
    then unsafePerformIO $ do
        withBytes x $ \ x' -> do
            withBytes y $ \ y' -> do
                result <- botan_constant_time_compare x' y' (fromIntegral $ ByteString.length x)
                case result of
                    0 -> return True
                    _ -> return False
    else False 

-- | int botan_scrub_mem(void* mem, size_t bytes);
foreign import ccall unsafe botan_scrub_mem :: Ptr () -> CSize -> IO CInt

-- I'm not entirely sure what this should be
-- Rather, this should be used in a `ScrubedBytes` implementation
botanScrubMem :: ForeignPtr a -> Int -> IO ()
botanScrubMem foreignPtr sz = withForeignPtr foreignPtr $ \ ptr -> do
    throwBotanIfNegative_ $ botan_scrub_mem (castPtr ptr) (fromIntegral sz)

type BotanHexFlag = Word32

-- NOTE: Not actually a botan constant
pattern BOTAN_FFI_HEX_NONE = 0 :: BotanHexFlag
pattern BOTAN_FFI_HEX_LOWER_CASE = 1 :: BotanHexFlag

-- | int botan_hex_encode(const uint8_t *x, size_t len, char *out, uint32_t flags)
-- NOTE: Return type is CInt, not BotanErrorCode. Function is explicit about return values.
foreign import ccall unsafe botan_hex_encode :: Ptr Word8 -> CSize -> Ptr CChar -> Word32 -> IO CInt

-- | Performs hex encoding of binary data in x of size len bytes. The output buffer out must be of at least x*2 bytes in size. If flags contains BOTAN_FFI_HEX_LOWER_CASE, hex encoding will only contain lower-case letters, upper-case letters otherwise. Returns 0 on success, 1 otherwise.
-- NOTE: Should this be used vs Data.ByteArray.Encoding ?
-- TODO: USE FLAG ARGUMENT?
-- DISCUSS: Handling of positive return code / BOTAN_FFI_INVALID_VERIFIER?
-- DISCUSS: Use of Text.decodeUtf8 - bad, partial function! - but safe here?
botanHexEncodeText :: Bool -> ByteString -> Text
botanHexEncodeText lower ba = Text.decodeUtf8 $ unsafePerformIO hex where 
    bytelen = ByteString.length ba
    hexlen = 2 * bytelen
    hex = withBytes ba $ \ ba' -> do
        allocBytes hexlen $ \ bb -> do
            throwBotanIfNegative_ $ botan_hex_encode ba' (fromIntegral bytelen) bb $ if lower
                then BOTAN_FFI_HEX_LOWER_CASE
                else BOTAN_FFI_HEX_NONE

-- | int botan_hex_decode(const char *hex_str, size_t in_len, uint8_t *out, size_t *out_len)
foreign import ccall unsafe botan_hex_decode :: Ptr CChar -> CSize -> Ptr Word8 -> Ptr CSize -> IO BotanErrorCode

-- | "Hex decode some data"
-- NOTE: Should this be used vs Data.ByteArray.Encoding ?
-- DISCUSS: Return value, maybe vs exception
-- DISCUSS: Botan documentation is lacking here
-- WARNING: Does not actually check that len is a multiple of 2
-- Could ByteString.pack . Text.unpack for efficiency, but is unsafe and requires
--  that the Text only include hex chars and is of even length
-- DISCUSS: Ignoring the Ptr CSize that returns the actual decoded length.
--  We need the array (and thus its length) /before/ we call botan_hex_decode :/
botanHexDecodeText :: Text -> ByteString
botanHexDecodeText txt = unsafePerformIO ba where 
    bs = Text.encodeUtf8 txt
    hexlen = Text.length txt
    bytelen = div (hexlen + 1) 2
    ba = allocBytes bytelen $ \ bytes -> do
        withBytes bs $ \ hex -> do
            alloca $ \ szPtr -> do
                throwBotanIfNegative_ $ botan_hex_decode hex (fromIntegral hexlen) bytes szPtr

-- | int botan_base64_encode(const uint8_t* x, size_t len, char* out, size_t* out_len);
foreign import ccall unsafe botan_base64_encode :: Ptr Word8 -> CSize -> Ptr CChar -> Ptr CSize -> IO BotanErrorCode

-- NOTE: Does not check tht base64Len == peek sizePtr
-- DISCUSS: Ignoring the Ptr CSize that returns the actual decoded length.
botanBase64EncodeText :: ByteString -> Text
botanBase64EncodeText ba = Text.decodeUtf8 $ unsafePerformIO base64 where 
    bytelen = ByteString.length ba
    base64Len = 4 * ceiling (fromIntegral bytelen / 3)
    base64 = withBytes ba $ \ ba' -> do
        allocBytes base64Len $ \ bb -> do
            alloca $ \ szPtr -> do
                throwBotanIfNegative_ $ botan_base64_encode ba' (fromIntegral bytelen) bb szPtr

-- | int botan_base64_decode(const char* base64_str, size_t in_len, uint8_t* out, size_t* out_len);
foreign import ccall unsafe botan_base64_decode :: Ptr CChar -> CSize -> Ptr Word8 -> Ptr CSize -> IO BotanErrorCode

-- | Ditto everything botanHexDecodeText
-- NOTE: Since must be
botanBase64DecodeText :: Text -> ByteString
botanBase64DecodeText txt = unsafePerformIO ba where 
    bs = Text.encodeUtf8 txt
    base64Len = Text.length txt
    padLen = Text.length $ Text.takeWhileEnd (== '=') txt
    bytelen = (3 * (div base64Len 4)) - (padLen)
    ba = allocBytes bytelen $ \ bytes -> do
        withBytes bs $ \ base64 -> do
            alloca $ \ szPtr -> do
                throwBotanIfNegative_ $ botan_base64_decode base64 (fromIntegral base64Len) bytes szPtr