{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}

-- | Display attributes
--
-- Attributes have three components: a foreground color, a background
-- color, and a style mask. The simplest attribute is the default
-- attribute, or 'defAttr'. Attributes can be modified with
-- 'withForeColor', 'withBackColor', and 'withStyle', e.g.,
--
-- @
--     defAttr \`withForeColor\` red
-- @
--
-- 'Image' constructors often require an 'Attr' to indicate the
-- attributes used in the image, e.g.,
--
-- @
--     string (defAttr \`withForeColor\` red) "this text will be red"
-- @
--
-- The appearance of 'Image's using 'defAttr' is determined by the The
-- terminal, so this is not something VTY can control. The user is free
-- to The define the color scheme of the terminal as they see fit.
--
-- The value 'currentAttr' will keep the attributes of whatever was
-- output previously.
module Graphics.Vty.Attributes
  ( module Graphics.Vty.Attributes.Color

  , Attr(..)
  , FixedAttr(..)
  , MaybeDefault(..)
  , defAttr
  , currentAttr

  -- * Styles
  , Style
  , withStyle
  , standout
  , italic
  , strikethrough
  , underline
  , reverseVideo
  , blink
  , dim
  , bold
  , defaultStyleMask
  , styleMask
  , hasStyle

  -- * Setting attribute colors
  , withForeColor
  , withBackColor

  -- * Setting hyperlinks
  , withURL
  )
where

import Control.DeepSeq
import Data.Bits
import Data.Text (Text)
import Data.Word
import GHC.Generics

import Graphics.Vty.Attributes.Color
import Data.MemoTrie
import Data.MemoTrie.Instances.Text ()

-- | A display attribute defines the Color and Style of all the
-- characters rendered after the attribute is applied.
--
-- At most 256 colors, picked from a 240 and 16 color palette, are
-- possible for the background and foreground. The 240 colors and
-- 16 colors are points in different palettes. See Color for more
-- information.
data Attr = Attr
    { attrStyle :: !(MaybeDefault Style)
    , attrForeColor :: !(MaybeDefault Color)
    , attrBackColor :: !(MaybeDefault Color)
    , attrURL :: !(MaybeDefault Text)
    } deriving ( Eq, Show, Read, Generic, NFData )

instance HasTrie Attr where
  newtype (Attr :->: b) = AttrTrie { unAttrTrie :: Reg Attr :->: b }
  trie = trieGeneric AttrTrie
  untrie = untrieGeneric unAttrTrie
  enumerate = enumerateGeneric unAttrTrie

-- This could be encoded into a single 32 bit word. The 32 bit word is
-- first divided into 4 groups of 8 bits where: The first group codes
-- what action should be taken with regards to the other groups.
--      XXYYZZ__
--      XX - style action
--          00 => reset to default
--          01 => unchanged
--          10 => set
--      YY - foreground color action
--          00 => reset to default
--          01 => unchanged
--          10 => set
--      ZZ - background color action
--          00 => reset to default
--          01 => unchanged
--          10 => set
--      __ - unused
--
--  Next is the style flags
--      SURBDOI_
--      S - standout
--      U - underline
--      R - reverse video
--      B - blink
--      D - dim
--      O - bold
--      I - italic
--      _ - unused
--
--  Then the foreground color encoded into 8 bits.
--  Then the background color encoded into 8 bits.

-- | Specifies the display attributes such that the final style and
-- color values do not depend on the previously applied display
-- attribute. The display attributes can still depend on the terminal's
-- default colors (unfortunately).
data FixedAttr = FixedAttr
    { fixedStyle :: !Style
    , fixedForeColor :: !(Maybe Color)
    , fixedBackColor :: !(Maybe Color)
    , fixedURL       :: !(Maybe Text)
    } deriving ( Eq, Show )

-- | The style and color attributes can either be the terminal defaults.
-- Or be equivalent to the previously applied style. Or be a specific
-- value.
data MaybeDefault v = Default | KeepCurrent | SetTo !v
  deriving (Eq, Read, Show, Generic)

instance HasTrie v => HasTrie (MaybeDefault v) where
  newtype (MaybeDefault v :->: b) = MaybeDefaultTrie { unMaybeDefaultTrie :: Reg (MaybeDefault v) :->: b }
  trie = trieGeneric MaybeDefaultTrie
  untrie = untrieGeneric unMaybeDefaultTrie
  enumerate = enumerateGeneric unMaybeDefaultTrie

instance (NFData v) => NFData (MaybeDefault v) where
    rnf Default = ()
    rnf KeepCurrent = ()
    rnf (SetTo v) = rnf v

-- | Styles are represented as an 8 bit word. Each bit in the word is 1
-- if the style attribute assigned to that bit should be applied and 0
-- if the style attribute should not be applied.
type Style = Word8

-- | Valid style attributes include:
--
--      * standout
--
--      * underline
--
--      * reverseVideo
--
--      * blink
--
--      * dim
--
--      * bold/bright
--
--      * italic
--
--      * strikethrough (via the smxx/rmxx terminfo capabilities)
--
--  (The invisible, protect, and altcharset display attributes some
--  terminals support are not supported via VTY.)
standout, underline, reverseVideo, blink, dim, bold, italic, strikethrough :: Style
standout        = 0x01
underline       = 0x02
reverseVideo    = 0x04
blink           = 0x08
dim             = 0x10
bold            = 0x20
italic          = 0x40
strikethrough   = 0x80

defaultStyleMask :: Style
defaultStyleMask = 0x00

styleMask :: Attr -> Word8
styleMask attr
    = case attrStyle attr of
        Default  -> 0
        KeepCurrent -> 0
        SetTo v  -> v

-- | true if the given Style value has the specified Style set.
hasStyle :: Style -> Style -> Bool
hasStyle s bitMask = ( s .&. bitMask ) /= 0

-- | Set the foreground color of an `Attr'.
withForeColor :: Attr -> Color -> Attr
withForeColor attr c = attr { attrForeColor = SetTo c }

-- | Set the background color of an `Attr'.
withBackColor :: Attr -> Color -> Attr
withBackColor attr c = attr { attrBackColor = SetTo c }

-- | Add the given style attribute
withStyle :: Attr -> Style -> Attr
withStyle attr 0 = attr
withStyle attr styleFlag = attr { attrStyle = SetTo $ styleMask attr .|. styleFlag }

-- | Add a hyperlinked URL using the proposed [escape sequences for
-- hyperlinked
-- URLs](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda).
-- These escape sequences are comparatively new and aren't widely
-- supported in terminal emulators yet, but most terminal emulators
-- that don't know about these sequences will ignore these sequences,
-- and therefore this should fall back sensibly. In some cases they
-- won't and this will result in garbage, so this is why hyperlinking is
-- disabled by default, in which case this combinator has no observable
-- effect. To enable it, enable 'Hyperlink' mode on your Vty output
-- interface.
withURL :: Attr -> Text -> Attr
withURL attr url = attr { attrURL = SetTo url }

-- | Sets the style, background color and foreground color to the
-- default values for the terminal. There is no easy way to determine
-- what the default background and foreground colors are.
defAttr :: Attr
defAttr = Attr Default Default Default Default

-- | Keeps the style, background color and foreground color that was
-- previously set. Used to override some part of the previous style.
--
-- EG: current_style `withForeColor` brightMagenta
--
-- Would be the currently applied style (be it underline, bold, etc) but
-- with the foreground color set to brightMagenta.
currentAttr :: Attr
currentAttr = Attr KeepCurrent KeepCurrent KeepCurrent KeepCurrent
