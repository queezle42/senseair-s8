module SenseairS8 (
  main
) where

import Control.Concurrent (threadDelay)
import Control.Exception
import Control.Monad
import Data.Bits ((.&.), (.|.), shiftL, shiftR)
import Data.ByteString qualified as BS
import Data.Digest.CRC16
import Data.List (splitAt)
import Data.Word
import Prelude
import System.Environment
import System.IO
import System.Serial
import System.Timeout
import System.Posix (handleToFd, fdToHandle)

-- Documentation overview:
-- https://senseair.com/products/size-counts/s8-lp/
--
-- Manual:
-- https://rmtplusstoragesenseair.blob.core.windows.net/docs/Dev/publicerat/TDE2067.pdf

main :: IO ()
main = do

  [tty] <- getArgs

  bracket
    (openSerial tty B9600 8 One NoParity NoFlowControl)
    hClose
    \h -> do
      hSetBinaryMode h True
      fd <- handleToFd h
      attrs <- getTerminalAttributes fd
      -- List of Terminal Attributes derived from `cfmakeraw (3)`
      let disable = [
            EchoLF,
            EnableEcho,
            ExtendedFunctions,
            IgnoreBreak,
            IgnoreCR,
            InterruptOnBreak,
            KeyboardInterrupts,
            MapCRtoLF,
            MapLFtoCR,
            MarkParityErrors,
            ProcessInput,
            ProcessOutput,
            StartStopInput,
            StartStopOutput,
            StripHighBit
            ]
      let rawMode = foldl withoutMode attrs disable
      setTerminalAttributes fd rawMode Immediately
      h <- fdToHandle fd
      forever do
        handle (\(ex :: SomeException) -> print ex) do
          value <- readSenseair h
          hPrint stderr value
        threadDelay 4_000_000

readSenseair :: Handle -> IO Word16
readSenseair h = do
  BS.hPutStr h "\xfe\x04\0\0\0\x04\xe5\xc6"
  timeout 250_000 (BS.hGetSome h 13) >>= \case
    Nothing -> fail "Sensor communication timeout reached"
    Just line -> do
      --hPrint stderr line

      (message, [crcl, crch]) <- pure $ splitAt 11 (BS.unpack line)
      when (crc16 message /= combine crch crcl) do
        fail "Invalid CRC"

      [0xfe, 0x04, 8, sh, sl, _, _, _, _, co2h, co2l] <- pure message

      let
        status = combine sh sl
        co2 = combine co2h co2l

      when (status /= 0) do
        -- TODO use testBit to convert status into errors
        fail (mconcat ["Received error status ", show status])

      pure co2

combine :: Word8 -> Word8 -> Word16
combine h l = shiftL (fromIntegral h) 8 .|. fromIntegral l
