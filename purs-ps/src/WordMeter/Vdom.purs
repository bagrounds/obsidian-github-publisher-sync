module WordMeter.Vdom
  ( Node
  , Attribute
  , Style
  , Listener(..)
  , text
  , element
  , div_
  , button
  , span_
  , details_
  , summary_
  , pre_
  , input
  , label_
  , attribute
  , className
  , testId
  , buttonType
  , style
  , onClick
  , onCheckboxChange
  , mount
  , ensureStylesheetLinked
  ) where

import Prelude

import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..))
import Effect (Effect)

data Node
  = ElementNode ElementSpec
  | TextNode String

type ElementSpec =
  { tag :: String
  , attributes :: Array Attribute
  , styles :: Array Style
  , listeners :: Array Listener
  , children :: Array Node
  }

type Attribute = { name :: String, value :: String }
type Style = { property :: String, value :: String }

-- | A DOM listener tagged by its event shape. Click handlers take no
-- | argument; checkbox change handlers receive the new checked state.
-- | Keeping the algebra closed (rather than a single `eventName + Foreign`
-- | constructor) lets the renderer dispatch through a typed FFI shim
-- | for each event kind.
data Listener
  = ClickListener (Effect Unit)
  | CheckboxChangeListener (Boolean -> Effect Unit)

text :: String -> Node
text = TextNode

element :: String -> Array Attribute -> Array Style -> Array Listener -> Array Node -> Node
element tag attributes styles listeners children =
  ElementNode { tag, attributes, styles, listeners, children }

div_ :: Array Attribute -> Array Style -> Array Node -> Node
div_ attributes styles children = element "div" attributes styles [] children

button :: Array Attribute -> Array Style -> Array Listener -> Array Node -> Node
button = element "button"

span_ :: Array Attribute -> Array Style -> Array Node -> Node
span_ attributes styles children = element "span" attributes styles [] children

details_ :: Array Attribute -> Array Style -> Array Node -> Node
details_ attributes styles children = element "details" attributes styles [] children

summary_ :: Array Attribute -> Array Style -> Array Listener -> Array Node -> Node
summary_ = element "summary"

pre_ :: Array Attribute -> Array Style -> Array Node -> Node
pre_ attributes styles children = element "pre" attributes styles [] children

input :: Array Attribute -> Array Style -> Array Listener -> Node
input attributes styles listeners = element "input" attributes styles listeners []

label_ :: Array Attribute -> Array Style -> Array Node -> Node
label_ attributes styles children = element "label" attributes styles [] children

attribute :: String -> String -> Attribute
attribute name value = { name, value }

testId :: String -> Attribute
testId = attribute "data-testid"

className :: String -> Attribute
className = attribute "class"

buttonType :: String -> Attribute
buttonType = attribute "type"

style :: String -> String -> Style
style property value = { property, value }

onClick :: Effect Unit -> Listener
onClick = ClickListener

onCheckboxChange :: (Boolean -> Effect Unit) -> Listener
onCheckboxChange = CheckboxChangeListener

foreign import data Element :: Type

foreign import findElementById
  :: (forall a. Maybe a)
  -> (forall a. a -> Maybe a)
  -> String
  -> Effect (Maybe Element)
foreign import createElementInDocument :: String -> Effect Element
foreign import createTextNodeInDocument :: String -> Effect Element
foreign import setAttributeOnElement :: String -> String -> Element -> Effect Unit
foreign import setStyleOnElement :: String -> String -> Element -> Effect Unit
foreign import attachClickListener :: Element -> Effect Unit -> Effect Unit
foreign import attachCheckboxChangeListener
  :: Element -> (Boolean -> Effect Unit) -> Effect Unit
foreign import appendChildToElement :: Element -> Element -> Effect Unit
foreign import removeAllChildrenFromElement :: Element -> Effect Unit
foreign import ensureStylesheetLinked :: String -> Effect Unit

mount :: String -> Node -> Effect Unit
mount hostId tree = do
  hostMaybe <- findElementById Nothing Just hostId
  case hostMaybe of
    Nothing -> pure unit
    Just host -> do
      removeAllChildrenFromElement host
      child <- renderNode tree
      appendChildToElement host child

renderNode :: Node -> Effect Element
renderNode (TextNode value) = createTextNodeInDocument value
renderNode (ElementNode spec) = do
  node <- createElementInDocument spec.tag
  traverse_ (applyAttribute node) spec.attributes
  traverse_ (applyStyle node) spec.styles
  traverse_ (applyListener node) spec.listeners
  traverse_ (appendRenderedChild node) spec.children
  pure node

applyAttribute :: Element -> Attribute -> Effect Unit
applyAttribute node attr = setAttributeOnElement attr.name attr.value node

applyStyle :: Element -> Style -> Effect Unit
applyStyle node decl = setStyleOnElement decl.property decl.value node

applyListener :: Element -> Listener -> Effect Unit
applyListener node = case _ of
  ClickListener handler -> attachClickListener node handler
  CheckboxChangeListener handler -> attachCheckboxChangeListener node handler

appendRenderedChild :: Element -> Node -> Effect Unit
appendRenderedChild parent child = renderNode child >>= appendChildToElement parent
