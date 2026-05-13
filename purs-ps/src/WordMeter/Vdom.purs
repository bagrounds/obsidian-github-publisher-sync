module WordMeter.Vdom
  ( Node
  , Attribute
  , Style
  , Listener
  , text
  , element
  , div_
  , button
  , span_
  , details_
  , summary_
  , pre_
  , attribute
  , testId
  , buttonType
  , style
  , onClick
  , mount
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
type Listener = { eventName :: String, handler :: Effect Unit }

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

attribute :: String -> String -> Attribute
attribute name value = { name, value }

testId :: String -> Attribute
testId = attribute "data-testid"

buttonType :: String -> Attribute
buttonType = attribute "type"

style :: String -> String -> Style
style property value = { property, value }

onClick :: Effect Unit -> Listener
onClick handler = { eventName: "click", handler }

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
foreign import appendChildToElement :: Element -> Element -> Effect Unit
foreign import removeAllChildrenFromElement :: Element -> Effect Unit

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
applyListener node listener = attachClickListener node listener.handler

appendRenderedChild :: Element -> Node -> Effect Unit
appendRenderedChild parent child = renderNode child >>= appendChildToElement parent
