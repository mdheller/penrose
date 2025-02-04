-- {-# LANGUAGE TemplateHaskell, StandaloneDeriving #-}
{-# LANGUAGE RankNTypes     #-}
{-# LANGUAGE ExplicitForAll #-}

module Penrose.Functions
  ( compDict
  , compSignatures
  , objFuncDict
  , objSignatures
  , constrFuncDict
  , constrSignatures
  , invokeComp
  , invokeOptFn
  , defaultObjFnsOf
  , defaultConstrsOf
  , OptFn
  , OptSignatures
  ) where

import           Data.Aeson            (toJSON)
import           Data.Fixed            (mod')
import           Data.List             (find, findIndex, maximumBy, nub, sort)
import qualified Data.Map.Strict       as M
import           Data.Maybe            (fromMaybe)
import qualified Data.MultiMap         as MM
import           Debug.Trace
import           Penrose.Shapes
import           Penrose.Transforms
import           Penrose.Util
import           System.Random         (StdGen, mkStdGen, randomR)
import           System.Random.Shuffle (shuffle')

default (Int, Float) -- So we don't default to Integer, which is 10x slower than Int (?)

-- genShapeType $ shapeTypes shapeDefs

--------------------------------------------------------------------------------
type FuncName = String

type OptSignatures = MM.MultiMap String [ArgType]

-- TODO: should computations be overloaded?
type CompSignatures = M.Map String ([ArgType], ArgType)

type OptFn a = [ArgVal a] -> a

type ObjFnOn a = [ArgVal a] -> a

type ConstrFnOn a = [ArgVal a] -> a

type CompFnOn a = [ArgVal a] -> StdGen -> (ArgVal a, StdGen)

type ObjFn
   = forall a. (Autofloat a) =>
                 [ArgVal a] -> a

type ConstrFn
   = forall a. (Autofloat a) =>
                 [ArgVal a] -> a

type CompFn
   = forall a. (Autofloat a) =>
                 [ArgVal a] -> StdGen -> (ArgVal a, StdGen)

-- | computations that do not use randomization
type ConstCompFn
   = forall a. (Autofloat a) =>
                 [ArgVal a] -> ArgVal a

-- TODO: are the Info types still needed?
type Weight a = a

type ObjFnInfo a = (ObjFnOn a, Weight a, [Value a])

type ConstrFnInfo a = (ConstrFnOn a, Weight a, [Value a])

data FnInfo a
  = ObjFnInfo a
  | ConstrFnInfo a

-- TODO: the functions can just be looked up and checked once, don't need to repeat
invokeOptFn ::
     (Autofloat a)
  => M.Map String (OptFn a)
  -> FuncName
  -> [ArgVal a]
  -> OptSignatures
  -> a
invokeOptFn dict n args signatures =
  let sigs =
        case signatures MM.! n of
          [] -> noSignatureError n
          l  -> l
      args' = checkArgsOverload args sigs n
      f = fromMaybe (noFunctionError n) (M.lookup n dict)
  in f args
    -- in f args'

-- For a very limited form of supertyping...
linelike :: Autofloat a => Shape a -> Bool
linelike shape = fst shape == "Line" || fst shape == "Arrow"

--------------------------------------------------------------------------------
-- Computations
compDict :: (Autofloat a) => M.Map String (CompFnOn a)
compDict =
  M.fromList
    [ ("rgba", constComp rgba)
    , ("atan", constComp arctangent)
    , ("calcVectorsAngle", constComp calcVectorsAngle)
    , ("calcVectorsAngleWithOrigin", constComp calcVectorsAngleWithOrigin)
    , ("generateRandomReal", constComp generateRandomReal)
    , ("calcNorm", constComp calcNorm)
    , ("bboxWidth", constComp bboxWidth)
    , ("bboxHeight", constComp bboxHeight)
    , ("intersectionX", constComp intersectionX)
    , ("intersectionY", constComp intersectionY)
    , ("midpointX", constComp midpointX)
    , ("midpointY", constComp midpointY)
    , ("average", constComp average)
    , ("len", constComp len)
    , ("computeSurjectionLines", computeSurjectionLines)
    , ("lineLeft", constComp lineLeft)
    , ("lineRight", constComp lineRight)
    , ("interpolate", constComp interpolate)
    , ("sampleFunction", sampleFunction)
    , ("fromDomain", fromDomain)
    , ("applyFn", constComp applyFn)
    , ("norm_", constComp norm_) -- type: any two GPIs with centers (getX, getY)
    , ("midpointPathX", constComp midpointPathX)
    , ("midpointPathY", constComp midpointPathY)
    , ("sizePathX", constComp sizePathX)
    , ("sizePathY", constComp sizePathY)
    , ("makeRegionPath", constComp makeRegionPath)
    , ("sampleFunctionArea", sampleFunctionArea)
    , ("makeCurve", makeCurve)
    , ("triangle", constComp triangle)
    , ("shared", constComp sharedP)
    , ("angle", constComp angleOf)
    , ("perpX", constComp perpX)
    , ("perpY", constComp perpY)
    , ("perpPath", constComp perpPath)
    , ("get", constComp get')
    , ("projectAndToScreen", constComp projectAndToScreen)
    , ("projectAndToScreen_list", constComp projectAndToScreen_list)
    , ("scaleLinear", constComp scaleLinear')
    , ("slerp", constComp slerp')
    , ("mod", constComp modSty)
    , ("halfwayPoint", constComp halfwayPoint')
    , ("normalOnSphere", constComp normalOnSphere')
    , ("arcPath", constComp arcPath')
    , ("angleBisector", constComp angleBisector')
    , ("tangentLineSX", constComp tangentLineSX)
    , ("tangentLineSY", constComp tangentLineSY)
    , ("tangentLineEX", constComp tangentLineEX)
    , ("tangentLineEY", constComp tangentLineEY)
    , ("polygonizeCurve", constComp polygonizeCurve)
    , ("setOpacity", constComp setOpacity)
    , ("bbox", constComp bbox')
    , ("min", constComp min')
    , ("max", constComp max')
    , ("pathFromPoints", constComp pathFromPoints)
    , ("join", constComp joinPath)
        -- Transformations
    , ("rotate", constComp rotate)
    , ("rotateAbout", constComp rotateAbout)
    , ("scale", constComp scale)
    , ("translate", constComp translate)
    , ("andThen", constComp andThen)
    , ("transformSRT", constComp transformSRT)
    , ("mkPoly", constComp mkPoly)
    , ("unitSquare", constComp unitSquare)
    , ("unitCircle", constComp unitCircle)
    , ("testTriangle", constComp testTri)
    , ("testNonconvexPoly", constComp testNonconvexPoly)
    , ("randomPolygon", randomPolygon)
    , ("midpoint", noop) -- TODO
    , ("sampleMatrix", noop) -- TODO
    , ("sampleReal", noop) -- TODO
    , ("sampleVectorIn", noop) -- TODO
    , ("intersection", noop) -- TODO
    , ("determinant", noop) -- TODO
    , ("apply", noop) -- TODO
    ] -- TODO: port existing comps

compSignatures :: CompSignatures
compSignatures =
  M.fromList
    [ ( "rgba"
      , ( [ValueT FloatT, ValueT FloatT, ValueT FloatT, ValueT FloatT]
        , ValueT ColorT))
    , ("atan", ([ValueT FloatT], ValueT FloatT))
    , ( "calcVectorsAngle"
      , ( [ ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          ]
        , ValueT FloatT))
    , ( "calcVectorsAngleCos"
      , ( [ ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          ]
        , ValueT FloatT))
    , ( "calcVectorsAngleWithOrigin"
      , ( [ ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          , ValueT FloatT
          ]
        , ValueT FloatT))
    , ("generateRandomReal", ([], ValueT FloatT))
    , ( "calcNorm"
      , ( [ValueT FloatT, ValueT FloatT, ValueT FloatT, ValueT FloatT]
        , ValueT FloatT))
    , ("intersectionX", ([GPIType "Arrow", GPIType "Arrow"], ValueT FloatT))
    , ("intersectionY", ([GPIType "Arrow", GPIType "Arrow"], ValueT FloatT))
    , ("bboxHeight", ([GPIType "Arrow", GPIType "Arrow"], ValueT FloatT))
    , ("bboxWidth", ([GPIType "Arrow", GPIType "Arrow"], ValueT FloatT))
    , ("len", ([GPIType "Arrow"], ValueT FloatT))
    , ( "computeSurjectionLines"
      , ( [ ValueT IntT
          , GPIType "Line"
          , GPIType "Line"
          , GPIType "Line"
          , GPIType "Line"
          ]
        , ValueT PtListT))
    , ( "lineLeft"
      , ([ValueT FloatT, GPIType "Arrow", GPIType "Arrow"], ValueT PtListT))
    , ("interpolate", ([ValueT PtListT, ValueT StrT], ValueT PathDataT))
    , ("sampleFunction", ([ValueT IntT, AnyGPI, AnyGPI], ValueT PtListT))
    , ("midpointX", ([AnyGPI], ValueT FloatT))
    , ("midpointY", ([AnyGPI], ValueT FloatT))
    , ("fromDomain", ([ValueT PtListT], ValueT FloatT))
    , ("applyFn", ([ValueT PtListT, ValueT FloatT], ValueT FloatT))
    , ("norm_", ([ValueT PtListT, ValueT FloatT], ValueT FloatT)) -- type: any two GPIs with centers (getX, getY)
    , ("midpointPathX", ([ValueT PtListT], ValueT FloatT))
    , ("midpointPathY", ([ValueT PtListT], ValueT FloatT))
    , ("sizePathX", ([ValueT PtListT], ValueT FloatT))
    , ("sizePathY", ([ValueT PtListT], ValueT FloatT))
    , ("tangentLineSX", ([ValueT PtListT, ValueT FloatT], ValueT FloatT))
    , ("tangentLineSY", ([ValueT PtListT, ValueT FloatT], ValueT FloatT))
    , ("tangentLineEX", ([ValueT PtListT, ValueT FloatT], ValueT FloatT))
    , ("tangentLineEY", ([ValueT PtListT, ValueT FloatT], ValueT FloatT))
    , ("makeRegionPath", ([GPIType "Curve", GPIType "Line"], ValueT PathDataT))
        -- ("len", ([GPIType "Arrow"], ValueT FloatT))
        -- ("bbox", ([GPIType "Arrow", GPIType "Arrow"], ValueT StrT)), -- TODO
        -- ("sampleMatrix", ([], ValueT StrT)), -- TODO
        -- ("sampleVectorIn", ([], ValueT StrT)), -- TODO
        -- ("intersection", ([], ValueT StrT)), -- TODO
        -- ("determinant", ([], ValueT StrT)), -- TODO
        -- ("apply", ([], ValueT StrT)) -- TODO
    ]

invokeComp ::
     (Autofloat a)
  => FuncName
  -> [ArgVal a]
  -> CompSignatures
  -> StdGen
  -> (ArgVal a, StdGen)
invokeComp n args sigs g
    -- TODO: Improve computation function typechecking to allow for genericity #164
        -- (argTypes, retType) =
            -- fromMaybe (noSignatureError n) (M.lookup n compSignatures)
        -- args'  = checkArgs args argTypes n
 =
  let f = fromMaybe (noFunctionError n) (M.lookup n compDict)
      (ret, g') = f args g
  in (ret, g')
       -- if checkReturn ret retType then (ret, g') else
       --  error ("invalid return value \"" ++ show ret ++ "\" of computation \"" ++ show n ++ "\". expected type is \"" ++ show retType ++ "\"")

-- | 'constComp' is a wrapper for computation functions that do not use randomization
constComp :: ConstCompFn -> CompFn
constComp f = \args g -> (f args, g) -- written in the lambda fn style to be more readable

--------------------------------------------------------------------------------
-- Objectives
-- Weights
repelWeight :: (Autofloat a) => a
repelWeight = 10000000

-- | 'objFuncDict' stores a mapping from the name of objective functions to the actual implementation
objFuncDict ::
     forall a. (Autofloat a)
  => M.Map String (ObjFnOn a)
objFuncDict =
  M.fromList
    [ ("near", near)
    , ("center", center)
    , ("centerX", centerX)
    , ("centerLabel", centerLabel)
    , ("centerArrow", centerArrow)
    , ("repel", (*) repelWeight . repel)
    , ("nearHead", nearHead)
    , ("topRightOf", topRightOf)
    , ("nearEndVert", nearEndVert)
    , ("nearEndHoriz", nearEndHoriz)
    , ("topLeftOf", topLeftOf)
    , ("above", above)
    , ("equal", equal)
    , ("distBetween", distBetween)
    , ("sameCenter", sameCenter)
        -- With the new transforms
    , ("nearT", nearT)
    , ("boundaryIntersect", boundaryIntersect)
    , ("containsPoly", containsPoly)
    , ("disjointPoly", disjointPoly)
    , ("containsPolyPad", containsPolyPad)
    , ("disjointPolyPad", disjointPolyPad)
    , ("padding", padding)
    , ("containAndTangent", containAndTangent)
    , ("disjointAndTangent", disjointAndTangent)
    , ("containsPolyOfs", containsPolyOfs)
    , ("disjointPolyOfs", disjointPolyOfs)
    , ("polyOnCanvas", polyOnCanvas)
    , ("maximumSize", maximumSize)
    , ("minimumSize", minimumSize)
    , ("sameSize", sameSize)
    , ("smaller", smaller)
    , ("atPoint", atPoint)
    , ("atPoint2", atPoint2)
    , ("nearPoint", nearPoint)
    , ("nearPoint2", nearPoint2)
    , ("alignAlong", alignAlong)
    , ("orderAlong", orderAlong)
        -- ("sameX", sameX)
    ]

{-      ("centerLine", centerLine),
        ("increasingX", increasingX),
        ("increasingY", increasingY),
        ("horizontal", horizontal),
        ("upright", upright),
        ("xInRange", xInRange),
        ("yInRange", yInRange),
        ("orthogonal", orthogonal),
        ("toLeft", toLeft),
        ("between", between),
        ("ratioOf", ratioOf),
        ("sameY", sameY),
        -- ("sameX", (*) 0.6 `compose2` sameX),
        -- ("sameX", (*) 0.2 `compose2` sameX),
        ("repel", (*)  900000  `compose2` repel),
        -- ("repel", (*)  1000000  `compose2` repel),
        -- ("repel", (*)  10000  `compose2` repel),
        -- ("repel", repel),
        ("outside", outside),
        -}
objSignatures :: OptSignatures
objSignatures =
  MM.fromList
    [ ("near", [GPIType "Circle", GPIType "Circle"])
    , ("near", [GPIType "Image", GPIType "Text", ValueT FloatT, ValueT FloatT])
    , ( "nearHead"
      , [GPIType "Arrow", GPIType "Text", ValueT FloatT, ValueT FloatT])
    , ("center", [AnyGPI])
    , ("centerX", [ValueT FloatT])
    , ("repel", [AnyGPI, AnyGPI])
    , ("centerLabel", [AnyGPI, GPIType "Text"])
    , ("centerArrow", [GPIType "Arrow", GPIType "Square", GPIType "Square"])
    , ("centerArrow", [GPIType "Arrow", GPIType "Circle", GPIType "Circle"])
    , ("centerArrow", [GPIType "Arrow", GPIType "Text", GPIType "Text"])
    , ("topLeftOf", [GPIType "Text", GPIType "Square"])
    , ("topLeftOf", [GPIType "Text", GPIType "Rectangle"])
    , ("topRightOf", [GPIType "Text", GPIType "Square"])
    , ("topRightOf", [GPIType "Text", GPIType "Rectangle"])
    , ("nearEndVert", [GPIType "Line", GPIType "Text"])
    , ("nearEndHoriz", [GPIType "Line", GPIType "Text"])
        -- ("centerArrow", []) -- TODO
    ]

--------------------------------------------------------------------------------
-- Constraints
-- exterior point method: penalty function
penalty :: (Ord a, Floating a, Show a) => a -> a
penalty x = max x 0 ^ q -- weights should get progressively larger in cr_dist
  where
    q = 2 :: Int -- also, may need to sample OUTSIDE feasible set
            -- where q = 3

{-# INLINE penalty #-}
-- | 'constrFuncDict' stores a mapping from the name of constraint functions to the actual implementation
constrFuncDict ::
     forall a. (Autofloat a)
  => M.Map FuncName (ConstrFnOn a)
constrFuncDict = M.fromList $ map toPenalty flist
  where
    toPenalty (n, f) = (n, penalty . f)
    flist =
      [ ("at", at)
      , ("contains", contains)
      , ("sameHeight", sameHeight)
      , ("nearHead", nearHead)
      , ("smallerThan", smallerThan)
      , ("minSize", minSize)
      , ("maxSize", maxSize)
      , ("outsideOf", outsideOf)
      , ("overlapping", overlapping)
      , ("disjoint", disjoint)
      , ("inRange", (*) indivConstrWeight . inRange')
      , ("lessThan", lessThan)
      , ("onCanvas", onCanvas)
      , ("unit", unit')
      , ("hasNorm", hasNorm)
      ]

indivConstrWeight :: (Autofloat a) => a
indivConstrWeight = 1

constrSignatures :: OptSignatures
constrSignatures =
  MM.fromList
    [ ("at", [AnyGPI, ValueT FloatT, ValueT FloatT])
    , ("minSize", [AnyGPI])
    , ("maxSize", [AnyGPI])
    , ("smallerThan", [GPIType "Circle", GPIType "Circle"])
    , ("smallerThan", [GPIType "Circle", GPIType "Square"])
    , ("smallerThan", [GPIType "Square", GPIType "Circle"])
    , ("smallerThan", [GPIType "Square", GPIType "Square"])
    , ("outsideOf", [GPIType "Text", GPIType "Circle"])
    , ("contains", [GPIType "Circle", GPIType "Circle"])
    , ("contains", [GPIType "Square", GPIType "Arrow"])
    , ("contains", [GPIType "Circle", GPIType "Circle", ValueT FloatT])
    , ("contains", [GPIType "Circle", GPIType "Text"])
    , ("contains", [GPIType "Square", GPIType "Text"])
    , ("contains", [GPIType "Rectangle", GPIType "Text"])
    , ("contains", [GPIType "Square", GPIType "Circle", ValueT FloatT])
    , ("contains", [GPIType "Square", GPIType "Circle"])
    , ("contains", [GPIType "Circle", GPIType "Square"])
    , ("contains", [GPIType "Circle", GPIType "Rectangle"])
    , ("overlapping", [GPIType "Circle", GPIType "Circle"])
    , ("overlapping", [GPIType "Square", GPIType "Circle"])
    , ("overlapping", [GPIType "Circle", GPIType "Square"])
    , ("overlapping", [GPIType "Square", GPIType "Square"])
    , ("disjoint", [GPIType "Circle", GPIType "Circle"])
    , ("disjoint", [GPIType "Square", GPIType "Square"])
        -- ("lessThan", []) --TODO
    ]

--------------------------------------------------------------------------------
-- Type checker for objectives and constraints
checkArg :: (Autofloat a) => ArgVal a -> ArgType -> Bool
-- TODO: add warnings/errors (?)
checkArg (GPI _) AnyGPI             = True
checkArg _ AnyGPI                   = False
checkArg (GPI (t, _)) (OneOf l)     = t `elem` l
checkArg (GPI (t1, _)) (GPIType t2) = t1 == t2
checkArg (Val v) (ValueT t)         = typeOf v == t
checkArg _ _                        = False

matchWith args sig =
  length args == length sig && and (zipWith checkArg args sig)

checkArgs :: (Autofloat a) => [ArgVal a] -> [ArgType] -> String -> [ArgVal a]
checkArgs arguments sig n =
  if arguments `matchWith` sig
    then arguments
    else sigMismatchError n sig arguments

checkArgsOverload ::
     (Autofloat a) => [ArgVal a] -> [[ArgType]] -> String -> [ArgVal a]
checkArgsOverload arguments signatures n =
  if any (arguments `matchWith`) signatures
    then arguments
    else noMatchedSigError n signatures arguments

checkReturn :: (Autofloat a) => ArgVal a -> ArgType -> Bool
-- TODO: add warning
checkReturn ret@(Val v) (ValueT t) = typeOf v == t
checkReturn (GPI v) _ = error "checkReturn: Computations cannot return GPIs"

--------------------------------------------------------------------------------
-- Computation Functions
sampleFunction :: CompFn
-- Assuming domain and range are lines or arrows, TODO deal w/ points
-- TODO: discontinuous functions? not sure how to sample/model/draw consistently
sampleFunction [Val (IntV n), GPI domain, GPI range] g =
  let (dsx, dsy, dex, dey) =
        ( getNum domain "startX"
        , getNum domain "startY"
        , getNum domain "endX"
        , getNum domain "endY")
      (rsx, rsy, rex, rey) =
        ( getNum range "startX"
        , getNum range "startY"
        , getNum range "endX"
        , getNum range "endY")
      lower_left = (min dsx dex, min rsy rey)
      top_right = (max dsx dex, max rsy rey)
      (pts, g') = computeSurjection g n lower_left top_right
  in (Val $ PtListV pts, g')

-- Computes the surjection to lie inside a bounding box defined by the corners of a box
-- defined by four straight lines, assuming their lower/left coordinates come first.
-- Their intersections give the corners.
computeSurjectionLines :: CompFn
computeSurjectionLines args g =
  let (pts, g') = computeSurjectionLines' g args
  in (Val $ PtListV pts, g')

computeSurjectionLines' ::
     (Autofloat a) => StdGen -> [ArgVal a] -> ([Pt2 a], StdGen)
computeSurjectionLines' g args@[Val (IntV n), GPI left@("Line", _), GPI right@("Line", _), GPI bottom@("Line", _), GPI top@("Line", _)] =
  let lower_left = (getNum left "startX", getNum bottom "startY")
  in let top_right = (getNum right "startX", getNum top "startY")
     in computeSurjection g n lower_left top_right
-- Assuming left and bottom are perpendicular and share one point
computeSurjectionLines' g [Val (IntV n), GPI left@("Arrow", _), GPI bottom@("Arrow", _)] =
  let lower_left = (getNum left "startX", getNum left "startY")
  in let top_right = (getNum bottom "endX", getNum left "endY")
     in computeSurjection g n lower_left top_right

computeSurjection ::
     Autofloat a => StdGen -> Integer -> Pt2 a -> Pt2 a -> ([Pt2 a], StdGen)
computeSurjection g numPoints (lowerx, lowery) (topx, topy) =
  if numPoints < 2
    then error "Surjection needs to have >= 2 points"
    else let (xs_inner, g') = randomsIn g (numPoints - 2) (r2f lowerx, r2f topx)
             xs = lowerx : xs_inner ++ [topx] -- Include endpts so function covers domain
             xs_increasing = sort xs
             (ys_inner, g'') =
               randomsIn g' (numPoints - 2) (r2f lowery, r2f topy)
             ys = lowery : ys_inner ++ [topy] -- Include endpts so function is onto
             ys_perm = shuffle' ys (length ys) g'' -- Random permutation. TODO return g3?
        -- in (zip xs_increasing ys_perm, g'') -- len xs == len ys
         in (zip xs_increasing ys_perm, g'') -- len xs == len ys

-- calculates a line (of two points) intersecting the first axis, stopping before it leaves bbox of second axis
-- TODO rename lineLeft and lineRight
-- assuming a1 horizontal and a2 vertical, respectively
lineLeft :: ConstCompFn
lineLeft [Val (FloatV lineFrac), GPI a1@("Arrow", _), GPI a2@("Arrow", _)] =
  let a1_start = getNum a1 "startX"
  in let a1_len = abs (getNum a1 "endX" - a1_start)
     in let xpos = a1_start + lineFrac * a1_len
        in Val $ PtListV [(xpos, getNum a1 "startY"), (xpos, getNum a2 "endY")]

-- assuming a1 vert and a2 horiz, respectively
-- can this be written in terms of lineLeft?
lineRight :: ConstCompFn
lineRight [Val (FloatV lineFrac), GPI a1@("Arrow", _), GPI a2@("Arrow", _)] =
  let a1_start = getNum a1 "startY"
  in let a1_len = abs (getNum a1 "endY" - a1_start)
     in let ypos = a1_start + lineFrac * a1_len
        in Val $ PtListV [(getNum a2 "startX", ypos), (getNum a2 "endX", ypos)]

rgba :: ConstCompFn
rgba [Val (FloatV r), Val (FloatV g), Val (FloatV b), Val (FloatV a)] =
  Val (ColorV $ makeColor' r g b a)

arctangent :: ConstCompFn
arctangent [Val (FloatV d)] = Val (FloatV $ (atan d) / pi * 180)

calcVectorsAngle :: ConstCompFn
calcVectorsAngle [Val (FloatV sx1), Val (FloatV sy1), Val (FloatV ex1), Val (FloatV ey1), Val (FloatV sx2), Val (FloatV sy2), Val (FloatV ex2), Val (FloatV ey2)] =
  let (ax, ay) = (ex1 - sx1, ey1 - sy1)
      (bx, by) = (ex2 - sx2, ey2 - sy2)
      ab = ax * bx + ay * by
      na = sqrt (ax ^ 2 + ay ^ 2)
      nb = sqrt (bx ^ 2 + by ^ 2)
      angle = acos (ab / (na * nb)) / pi * 180.0
  in Val (FloatV angle)

calcVectorsAngleWithOrigin :: ConstCompFn
calcVectorsAngleWithOrigin [Val (FloatV sx1), Val (FloatV sy1), Val (FloatV ex1), Val (FloatV ey1), Val (FloatV sx2), Val (FloatV sy2), Val (FloatV ex2), Val (FloatV ey2)] =
  let (ax, ay) = (ex1 - sx1, ey1 - sy1)
      (bx, by) = (ex2 - sx2, ey2 - sy2)
      (cx, cy) = ((ax + bx) / 2.0, (ay + by) / 2.0)
      angle =
        if cy < 0
          then (atan (cy / cx) / pi * 180.0) * 2.0
          else 180.0 + (atan (cy / cx) / pi * 180.0) * 2.0
  in Val (FloatV $ -1.0 * angle)
        --     angle1 =  if ay < 0 then  (atan (ay / ax) / pi*180.0) else 180.0  +  (atan (ay / ax) / pi*180.0)
        --     angle2 =  if by < 0 then  (atan (by / bx) / pi*180.0) else 180.0 +   (atan  (by / bx) / pi*180.0)
        -- in if traceShowId angle1 > traceShowId angle2 then Val (FloatV $ -1 * angle1) else Val (FloatV $ -1 * angle2)

generateRandomReal :: ConstCompFn
generateRandomReal [] =
  let g1 = mkStdGen 16
      (x, g2) = (randomR (1, 15) g1) :: (Int, StdGen)
      y = fst (randomR (1, 15) g2) :: Int
  in Val (FloatV ((fromIntegral x) / (fromIntegral y)))

calcNorm :: ConstCompFn
calcNorm [Val (FloatV sx1), Val (FloatV sy1), Val (FloatV ex1), Val (FloatV ey1)] =
  let nx = (ex1 - sx1) ** 2.0
      ny = (ey1 - sy1) ** 2.0
      norm = sqrt (nx + ny + 0.5)
  in Val (FloatV norm)

linePts, arrowPts :: (Autofloat a) => Shape a -> (a, a, a, a)
linePts = arrowPts

arrowPts a =
  (getNum a "startX", getNum a "startY", getNum a "endX", getNum a "endY")

infinity :: Floating a => a
infinity = 1 / 0 -- x/0 == Infinity for any x > 0 (x = 0 -> Nan, x < 0 -> -Infinity)

intersectionX :: ConstCompFn
intersectionX [GPI a1@("Arrow", _), GPI a2@("Arrow", _)] =
  let (x0, y0, x1, y1) = arrowPts a1
      (x2, y2, x3, y3) = arrowPts a2
      det = (x0 - x1) * (y2 - y3) - (y0 - y1) * (x2 - x3)
  in Val $
     FloatV $
     if det == 0
       then infinity
       else (x0 * y1 - y0 * x1) * (x2 - x3) -
            (x0 - x1) * (x2 * x3 - y2 * y3) / det

intersectionY :: ConstCompFn
intersectionY [GPI a1@("Arrow", _), GPI a2@("Arrow", _)] =
  let (x0, y0, x1, y1) = arrowPts a1
      (x2, y2, x3, y3) = arrowPts a2
      det = (x0 - x1) * (y2 - y3) - (y0 - y1) * (x2 - x3)
  in Val $
     FloatV $
     if det == 0
       then infinity
       else (x0 * y1 - y0 * x1) * (x2 - x3) -
            (y0 - y1) * (x2 * x3 - y2 * y3) / det

len :: ConstCompFn
len [GPI a@("Arrow", _)] =
  let (x0, y0, x1, y1) = arrowPts a
  in Val $ FloatV $ dist (x0, y0) (x1, y1)

midpointX :: ConstCompFn
midpointX [GPI l] =
  if linelike l
    then let (x0, x1) = (getNum l "startX", getNum l "endX")
         in Val $ FloatV $ (x1 + x0) / 2
    else error "GPI type must be line-like"

midpointY :: ConstCompFn
midpointY [GPI l] =
  if linelike l
    then let (y0, y1) = (getNum l "startY", getNum l "endY")
         in Val $ FloatV $ (y1 + y0) / 2
    else error "GPI type must be line-like"

average :: ConstCompFn
average [Val (FloatV x), Val (FloatV y)] =
  let res = (x + y) / 2
  in Val $ FloatV res

norm_ :: ConstCompFn
norm_ [Val (FloatV x), Val (FloatV y)] = Val $ FloatV $ norm [x, y]

-- | Catmull-Rom spline interpolation algorithm
interpolateFn :: Autofloat a => [Pt2 a] -> [Elem a]
interpolateFn pts =
  let k = 1.5
      p0 = head pts
      chunks = repeat4 $ head pts : pts ++ [last pts]
      paths = map (chain k) chunks
      finalPath = Pt p0 : paths
  in finalPath
  where
    repeat4 xs = [take 4 . drop n $ xs | n <- [0 .. length xs - 4]]

-- Wrapper for interpolateFn
interpolate :: ConstCompFn
interpolate [Val (PtListV pts)] =
  let pathRes = interpolateFn pts
  in Val $ PathDataV $ [Open pathRes]

chain :: Autofloat a => a -> [(a, a)] -> Elem a
chain k [(x0, y0), (x1, y1), (x2, y2), (x3, y3)] =
  let cp1x = x1 + (x2 - x0) / 6 * k
      cp1y = y1 + (y2 - y0) / 6 * k
      cp2x = x2 - (x3 - x1) / 6 * k
      cp2y = y2 - (y3 - y1) / 6 * k
  in CubicBez ((cp1x, cp1y), (cp2x, cp2y), (x2, y2))

-- COMBAK: finish this
-- sampleCurve :: Autofloat a =>
--     StdGen -> Integer -> Pt2 a -> Pt2 a -> Bool -> Bool -> [Pt2 a]
-- sampleCurve g numPoints (lowerx, lowery) (topx, topy) =
--     if numPoints < 2 then error "Surjection needs to have >= 2 points"
--     else
--         let (xs_inner, g') = randomsIn g (numPoints - 2) (r2f lowerx, r2f topx)
--             xs = lowerx : xs_inner ++ [topx] -- Include endpts so function covers domain
--             (ys_inner, g'') = randomsIn g' (numPoints - 2) (r2f lowery, r2f topy)
--             ys = lowery : ys_inner ++ [topy] -- Include endpts so function is onto
--             xs_increasing = sort xs
--             ys_perm = shuffle' ys (length ys) g'' -- Random permutation. TODO return g3?
--         -- in (zip xs_increasing ys_perm, g'') -- len xs == len ys
--         in zip xs_increasing ys_perm -- len xs == len ys
-- From Shapes.hs, TODO factor out
sampleList :: (Autofloat a) => [a] -> StdGen -> (a, StdGen)
sampleList list g =
  let (idx, g') = randomR (0, length list - 1) g
  in (list !! idx, g')

-- sample random element from domain of function (relation)
fromDomain :: CompFn
fromDomain [Val (PtListV path)] g =
  let (x, g') = sampleList (middle $ map fst path) g
           -- let x = fst $ path !! 1 in
  in (Val $ FloatV x, g')
  where
    middle = init . tail

-- lookup element in function (relation) by making a Map
applyFn :: ConstCompFn
applyFn [Val (PtListV path), Val (FloatV x)] =
  case M.lookup x (M.fromList path) of
    Just y  -> Val (FloatV y)
    Nothing -> error "x element does not exist in function"

-- TODO: remove the unused functions in the next four
midpointPathX :: ConstCompFn
midpointPathX [Val (PtListV path)] =
  let xs = map fst path
      res = (maximum xs + minimum xs) / 2
  in Val $ FloatV res

midpointPathY :: ConstCompFn
midpointPathY [Val (PtListV path)] =
  let ys = map snd path
      res = (maximum ys + minimum ys) / 2
  in Val $ FloatV res

sizePathX :: ConstCompFn
sizePathX [Val (PtListV path)] =
  let xs = map fst path
      res = maximum xs - minimum xs
  in Val $ FloatV res

sizePathY :: ConstCompFn
sizePathY [Val (PtListV path)] =
  let ys = map snd path
      res = maximum ys - minimum ys
  in Val $ FloatV res

-- Compute path for an integral's shape (under a function, above the interval on which the function is defined)
makeRegionPath :: ConstCompFn
makeRegionPath [GPI fn@("Curve", _), GPI intv@("Line", _)] =
  let pt1 = Pt $ getPoint "start" intv
      pt2 = Pt $ getPoint "end" intv
                   -- Assume the function is a single open path consisting of a Pt elem, followed by CubicBez elements
                   -- (i.e. produced by `interpolate` with parameter "open")
      curve =
        case (getPathData fn) !! 0 of
          Open elems -> elems
          Closed elems ->
            error "makeRegionPath not implemented for closed paths"
      path = Closed $ pt1 : curve ++ [pt2]
  in Val (PathDataV [path])
-- Make determinant region
makeRegionPath [GPI a1, GPI a2] =
  if not (linelike a1 && linelike a2)
    then error "expected two linelike GPIs"
    else let xs@[sx1, ex1, sx2, ex2] = getXs a1 ++ getXs a2
             ys@[sy1, ey1, sy2, ey2] = getYs a1 ++ getYs a2
                   -- Third coordinate is the vector addition, normalized for an origin that may not be (0, 0)
             regionPts =
               [ (sx1, sy1)
               , (ex1, ey1)
               , (ex1 + ex2 - sx1, ey1 + ey2 - sy1)
               , (ex2, ey2)
               ]
             path = Closed $ map Pt regionPts
         in Val (PathDataV [path])
  where
    getXs a = [getNum a "startX", getNum a "endX"]
    getYs a = [getNum a "startY", getNum a "endY"]

-- | Draws a filled region from domain to range with in-curved sides, assuming domain is above range
-- | Directionality: domain's right, then range's right, then range's left, then domain's left
-- TODO: when range's x is a lot smaller than the domain's x, or |range| << |domain|, the generated region crosses itself
-- You can see this by adjusting the interval size by *dragging the labels*
-- TODO: should account for thickness of domain and range
-- Assuming horizontal GPIs
sampleFunctionArea :: CompFn
sampleFunctionArea [x@(GPI domain), y@(GPI range)] g
                   -- Apply with default offsets
 = sampleFunctionArea [x, y, Val (FloatV 0.3), Val (FloatV 0.0)] g
sampleFunctionArea [GPI domain, GPI range, Val (FloatV xFrac), Val (FloatV yFrac)] g =
  if linelike domain && linelike range
    then let pt_tl = getPoint "start" domain
             pt_tr = getPoint "end" domain
             pt_br = getPoint "end" range
             pt_bl = getPoint "start" range
                        -- Compute dx (the x offset for the function's shape) as a fraction of width of the smaller interval
             width =
               min (abs (fst pt_tl - fst pt_tr)) (abs (fst pt_br - fst pt_bl))
             height = abs $ snd pt_bl - snd pt_tl
             dx = xFrac * width
             dy = yFrac * height
             x_offset = (dx, 0)
             y_offset = (0, dy)
             pt_midright = midpoint pt_tr pt_br -: x_offset +: y_offset
             pt_midleft = midpoint pt_bl pt_tl +: x_offset +: y_offset
             right_curve = interpolateFn [pt_tr, pt_midright, pt_br]
             left_curve = interpolateFn [pt_bl, pt_midleft, pt_tl]
                        -- TODO: not sure if this is right. do any points need to be included in the path?
             path =
               Closed $
               [Pt pt_tl, Pt pt_tr] ++
               right_curve ++ [Pt pt_br, Pt pt_bl] ++ left_curve
         in (Val $ PathDataV [path], g)
    else error "expected two linelike shapes"

-- Draw a curve from (x1, y1) to (x2, y2) with some point in the middle defining curvature
makeCurve :: CompFn
makeCurve [Val (FloatV x1), Val (FloatV y1), Val (FloatV x2), Val (FloatV y2), Val (FloatV dx), Val (FloatV dy)] g =
  let offset = (dx, dy)
      midpt = midpoint (x1, y1) (x2, y2) +: offset
      path = Open $ interpolateFn [(x1, y1), midpt, (x2, y2)]
  in (Val $ PathDataV [path], g)

-- Draw a triangle as the closure of three lines (assuming they define a valid triangle, i.e. intersect exactly at their endpoints)
triangle :: ConstCompFn
triangle [Val (FloatV x1), Val (FloatV y1), Val (FloatV x2), Val (FloatV y2), Val (FloatV x3), Val (FloatV y3)] =
  let path = Closed [Pt (x1, y1), Pt (x2, y2), Pt (x3, y3)]
  in Val $ PathDataV [path]
triangle [GPI e1@("Line", _), GPI e2@("Line", _), GPI e3@("Line", _)]
         -- TODO: what's the convention on the ordering of the lines?
 =
  let (v1, v2) = (getPoint "start" e1, getPoint "end" e1)
      v3_candidates =
        [ getPoint "start" e2
        , getPoint "end" e2
        , getPoint "start" e3
        , getPoint "end" e3
        ]
      v3 = furthestFrom (v1, v2) v3_candidates
      path = Closed [Pt v1, Pt v2, Pt v3]
  in Val $ PathDataV [path] {- trace ("path: " ++ show path) $ -}
  where
    furthestFrom :: (Autofloat a) => (Pt2 a, Pt2 a) -> [Pt2 a] -> Pt2 a
    furthestFrom (p1, p2) pts =
      fst $
      maximumBy (\p1 p2 -> compare (snd p1) (snd p2)) $
      map (\p -> (p, dist p p1 + dist p p2)) pts

sharedP :: ConstCompFn
sharedP [Val (FloatV a), Val (FloatV b), Val (FloatV c), Val (FloatV d)] =
  let xs = nub [a, b, c, d]
      common =
        case xs of
          []   -> error "no shared points between segments"
          x:xs -> x
  in Val $ FloatV common

angleOf :: ConstCompFn
angleOf [GPI l@("Line", _), Val (FloatV originX), Val (FloatV originY)] =
  let origin = (originX, originY)
      (start, end) = (getPoint "start" l, getPoint "end" l)
      endpoint =
        if origin == start
          then end
          else start -- Pick the point that's not the origin
      (rayX, rayY) = endpoint -: origin
      angleRad = atan2 rayY rayX
      angle = (angleRad * 180) / pi
  in Val $ FloatV angle

perp :: Autofloat a => Pt2 a -> Pt2 a -> Pt2 a -> a -> Pt2 a
perp start end base len =
  let dir = normalize' $ end -: start
      perpDir = (len *: (rot90 dir)) +: base
  in perpDir

perpX :: ConstCompFn
perpX [GPI l@("Line", _), Val (FloatV baseX), Val (FloatV baseY), Val (FloatV len)] =
  let (start, end) = (getPoint "start" l, getPoint "end" l)
  in Val $ FloatV $ fst $ perp start end (baseX, baseY) len

perpY :: ConstCompFn
perpY [GPI l@("Line", _), Val (FloatV baseX), Val (FloatV baseY), Val (FloatV len)] =
  let (start, end) = (getPoint "start" l, getPoint "end" l)
  in Val $ FloatV $ snd $ perp start end (baseX, baseY) len

perpPath :: ConstCompFn
perpPath [GPI r@("Line", _), GPI l@("Line", _), Val (FloatV size)] -- Euclidean
 =
  let (startR, endR) = (getPoint "start" r, getPoint "end" r)
      (startL, endL) = (getPoint "start" l, getPoint "end" l)
      dirR = normalize' $ endR -: startR
      dirL = normalize' $ endL -: startL
      ptL = startR +: (size *: dirL)
      ptR = startR +: (size *: dirR)
      ptLR = startR +: (size *: dirL) +: (size *: dirR)
             -- TODO: clean up this code
      path = Open $ [Pt ptL, Pt ptLR, Pt ptR]
  in Val $ PathDataV [path]
perpPath [Val (ListV p), Val (ListV q), Val (ListV tailv), Val (ListV headv), Val (FloatV arcLen)] -- Spherical
 =
  let (p', q') = (normalize p, normalize q)
             -- TODO: cache these calculations bc they're recomputed many times in Ray, Triangle, etc.
      (e1, e2) = (p', normalize (p' `cross` q')) -- e2 is normal to (e1, e3)
      e3 = normalize (e2 `cross` e1)
      local_normal_normal = normalize (tailv `cross` headv) -- The normal to the plane defined by the (headv, tailv) vectors, which is tangent to (p,q) at the point tailv
      pt_along_seg = circPtInPlane tailv local_normal_normal arcLen -- Start at the tail of the ray and move along the segment (pq) using its tangent
      pt_along_normal = circPtInPlane tailv e2 arcLen -- Start at the tail of the ray and move along the ray in the direction normal to (pq)
      n = 20
      arc_parallel_to_normal = slerp n 0.0 arcLen pt_along_seg e2 -- Move from the segment point in the direction normal to (pq)
      arc_parallel_to_seg =
        slerp n 0.0 arcLen pt_along_normal local_normal_normal -- Move from the ray point in the direction normal to the ray
             -- Note that the directions are chosen so that the directionality of the arcs match so they meet at a point
      pts = arc_parallel_to_normal ++ (tail . reverse) arc_parallel_to_seg -- Drop a point so they join better
  in Val $ LListV pts

-- NOTE: assumes that the curve has at least 3 points
tangentLine :: Autofloat a => a -> [Pt2 a] -> a -> (Pt2 a, Pt2 a)
tangentLine x ptList len =
  let i = fromMaybe 1 $ findIndex (\(a, _) -> abs (x - a) <= 1) ptList
      p0@(px, py) = ptList !! i
      p1 = nextPoint p0 $ drop (i - 1) ptList
      k = slope p0 p1
      dx = d / sqrt (1 + k ^ 2)
      dy = k * dx
      d = len / 2
  in ((px - dx, py - dy), (px + dx, py + dy))
        -- NOTE: instead of getting the immediate next point in the list, we search the rest of the list until a point that is numerically far enough from (x, y) is found, in order to compute the slope.
  where
    nextPoint (x, y) l =
      fromMaybe (error "tangentLine: cannot find next point") $
      find (\(x', y') -> abs (x - x') > epsd || abs (y - y') > epsd) l
    slope (x0, y0) (x1, y1) = (y1 - y0) / (x1 - x0)

tangentLineSX :: ConstCompFn
tangentLineSX [Val (PtListV curve), Val (FloatV x), Val (FloatV len)] =
  Val $ FloatV $ fst $ fst $ tangentLine x curve len

tangentLineSY :: ConstCompFn
tangentLineSY [Val (PtListV curve), Val (FloatV x), Val (FloatV len)] =
  Val $ FloatV $ snd $ fst $ tangentLine x curve len

tangentLineEX :: ConstCompFn
tangentLineEX [Val (PtListV curve), Val (FloatV x), Val (FloatV len)] =
  Val $ FloatV $ fst $ snd $ tangentLine x curve len

tangentLineEY :: ConstCompFn
tangentLineEY [Val (PtListV curve), Val (FloatV x), Val (FloatV len)] =
  Val $ FloatV $ snd $ snd $ tangentLine x curve len

polygonizeCurve :: ConstCompFn
polygonizeCurve [Val (IntV maxIter), Val (PathDataV curve)] =
  Val $ PtListV $ polygonizePath (fromIntegral maxIter) curve

bboxHeight :: ConstCompFn
bboxHeight [GPI a1@("Arrow", _), GPI a2@("Arrow", _)] =
  let ys@[y0, y1, y2, y3] = getYs a1 ++ getYs a2
      (ymin, ymax) = (minimum ys, maximum ys)
  in Val $ FloatV $ abs $ ymax - ymin
  where
    getYs a = [getNum a "startY", getNum a "endY"]

bboxWidth :: ConstCompFn
bboxWidth [GPI a1@("Arrow", _), GPI a2@("Arrow", _)] =
  let xs@[x0, x1, x2, x3] = getXs a1 ++ getXs a2
      (xmin, xmax) = (minimum xs, maximum xs)
  in Val $ FloatV $ abs $ xmax - xmin
  where
    getXs a = [getNum a "startX", getNum a "endX"]

bbox :: (Autofloat a) => Shape a -> Shape a -> [(a, a)]
bbox a1 a2 =
  if not (linelike a1 && linelike a2)
    then error "expected two linelike GPIs"
    else let xs@[x0, x1, x2, x3] = getXs a1 ++ getXs a2
             (xmin, xmax) = (minimum xs, maximum xs)
             ys@[y0, y1, y2, y3] = getYs a1 ++ getYs a2
             (ymin, ymax) = (minimum ys, maximum ys)
    -- Four bbox points in clockwise order (bottom left, bottom right, top right, top left)
         in [(xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax)]
  where
    getXs a = [getNum a "startX", getNum a "endX"]
    getYs a = [getNum a "startY", getNum a "endY"]

bbox' :: ConstCompFn
bbox' [GPI a1, GPI a2] = Val $ PtListV $ bbox a2 a2

min' :: ConstCompFn
min' [Val (FloatV x), Val (FloatV y)] = Val $ FloatV $ min x y

max' :: ConstCompFn
max' [Val (FloatV x), Val (FloatV y)] = Val $ FloatV $ max x y

noop :: CompFn
noop [] g = (Val (StrV "TODO"), g)

-- Set the opacity to a given fraction of the value.
setOpacity :: ConstCompFn
setOpacity [Val (ColorV (RGBA r g b a)), Val (FloatV frac)] =
  Val $ ColorV (RGBA r g b (r2f frac * a))

----------
get' :: ConstCompFn
get' [Val (ListV xs), Val (IntV i)] =
  let i' = (fromIntegral i) :: Int
  in if i' < 0 || i' >= length xs
       then error "out of bounds access in get'"
       else Val $ FloatV $ xs !! i'
get' [Val (TupV (x1, x2)), index] = get' [Val (ListV [x1, x2]), index]

projectVec ::
     Autofloat a
  => String
  -> Pt2 a
  -> Pt2 a
  -> a
  -> [a]
  -> [a]
  -> [a]
  -> a
  -> [a]
projectVec name hfov vfov r camera dir vec_math toScreen =
  let vec_camera = vec_math -. camera -- Camera at origin. TODO: rotate with dir
      [px, py, pz] = vec_camera
      vec_proj = (1 / pz) *. [px, py]
      vec_screen = toScreen *. vec_proj
      vec_proj_screen = vec_screen ++ [pz] -- TODO check denom 0. Also note z might be negative?
  in trace
       ("\n" ++
        "name: " ++
        name ++
        "\nvec_math: " ++
        show vec_math ++
        "\n||vec_math||: " ++
        show (norm vec_math) ++
        "\nvec_camera: " ++
        show vec_camera ++
        "\nvec_proj: " ++
        show vec_proj ++
        "\nvec_screen: " ++
        show vec_screen ++ "\nvec_proj_screen: " ++ show vec_proj_screen ++ "\n")
       vec_proj_screen

-- | For two points p, q, the easiest thing is to form an orthonormal basis e1=p, e2=(p x q)/|p x q|, e3=e2 x e1, then draw the arc as cos(t)e1 + sin(t)e3 for t between 0 and arccos(p . q) (Assuming p and q are unit)
slerp' :: ConstCompFn
slerp' [Val (ListV p), Val (ListV q), Val (IntV n)] -- Assuming unit p, q?
 =
  let (e1, e2) = (normalize p, normalize (p `cross` q)) -- (e1, e3) span the plane of p and q
      e3 = normalize (e2 `cross` e1)
      (t0, t1) = (0.0, angleBetweenRad p q) -- On a unit sphere, the angle between points is the length of the arc b/t them
      pts = slerp (fromIntegral n) t0 t1 e1 e3
  in Val $
     LListV $
     trace
       ("(e1, e2, e3): " ++
        show (e1, e2, e3) ++
        "\ndot results: " ++
        show [ei `dotL` ej | ei <- [e1, e2, e3], ej <- [e1, e2, e3]] ++
        "\n(p, q, angleBetweenRad): " ++
        show (p, q, t1) ++ "\npts: " ++ show pts)
       pts

-- TODO: how does this behave with negative numbers?
modSty :: ConstCompFn
modSty [Val (FloatV x), Val (FloatV m)] = Val $ FloatV $ (x `mod'` m) -- Floating mod

-- http://mathworld.wolfram.com/SphericalCoordinates.html
projectAndToScreen :: ConstCompFn
projectAndToScreen [Val (TupV hfov), Val (TupV vfov), Val (FloatV r), Val (ListV camera), Val (ListV dir), Val (ListV vec_math), Val (FloatV toScreen), Val (StrV name)] =
  Val $ ListV $ projectVec name hfov vfov r camera dir vec_math toScreen

projectAndToScreen_list :: ConstCompFn
projectAndToScreen_list [Val (TupV hfov), Val (TupV vfov), Val (FloatV r), Val (ListV camera), Val (ListV dir), Val (LListV spherePath), Val (FloatV toScreen), Val (StrV name)] =
  Val $
  PtListV $
  (map
     (\vmath ->
        let res = projectVec name hfov vfov r camera dir vmath toScreen
        in (res !! 0, res !! 1))
     spherePath)
     -- Discard z-coordinate for now

halfwayPoint' :: ConstCompFn -- Based off slerp'
halfwayPoint' [Val (ListV p), Val (ListV q)] =
  let (p', q') = (normalize p, normalize q)
      (e1, e2) = (p', normalize (p' `cross` q'))
      e3 = normalize (e2 `cross` e1)
      t = (angleBetweenRad p' q') / 2.0 -- Half the angle, or half the arc length
      r = circPtInPlane e1 e3 t
  in Val (ListV r)

normalOnSphere' :: ConstCompFn
normalOnSphere' [Val (ListV p), Val (ListV q), Val (ListV tailv), Val (FloatV arcLen)] =
  let normalv = normalize (p `cross` q)
      headv = circPtInPlane (normalize tailv) normalv arcLen -- Start at tailv (point on segment), move in normal direction by arcLen
  in Val (ListV headv)

-- Draw the arc on the sphere between the segment (pq) and the segment (qr) with some fixed radius
-- The angle between lines (pq, pr) is angle of the planes containing the great circles of the arcs
-- Find an orthonormal basis with the normal (n) of the sphere at a point, then the tangent vectors (t1, t2) of the plane at the point, where t1 is in the direction of one of the lines
-- t1 is found as `p - proj_q(p) |> normalize` (where p is the local origin and q is another point on the triangle)
-- Then draw the arc in the tangent plane from t1 to the angle, then translate it to the local origin
arcPath' :: ConstCompFn
arcPath' [Val (ListV p), Val (ListV q), Val (ListV r), Val (FloatV radius)] -- Radius is arc len
 =
  let normal = p
      (qp, rp) = (q -. p, r -. p)
      (qp_normal, rp_normal) = (q `cross` p, r `cross` p)
      theta = angleBetweenSigned normal qp_normal rp_normal -- The signed angle from qp normal to rp normal (in the tangent plane defined by `p`, where `p` is the normal that points outward from the sphere
      t1 = normalize (qp -. (proj normal qp)) -- tangent in qp direction
      t2 = t1 `cross` normal
      n = 20
      pts_origin = map (radius *.) $ slerp n 0 theta t1 t2 -- starts at qp segment
      pts = map (+. p) pts_origin -- Why does this arc lie on the sphere?
  in Val $ LListV pts

-- TODO: share some code betwen this and arcPath'?
angleBisector' :: ConstCompFn
angleBisector' [Val (ListV p), Val (ListV q), Val (ListV r), Val (FloatV radius)] -- Radius is arc len
 =
  let normal = p
      (qp, rp) = (q -. p, r -. p)
      (qp_normal, rp_normal) = (q `cross` p, r `cross` p)
      theta = (angleBetweenSigned normal qp_normal rp_normal) / 2.0
      t1 = normalize (qp -. (proj normal qp)) -- tangent in qp direction
      t2 = t1 `cross` normal
      pt_origin = (p +.) $ (radius *.) $ circPtInPlane t1 t2 theta -- starts at qp segment
  in Val $ ListV pt_origin

scaleLinear' :: ConstCompFn
scaleLinear' [Val (FloatV x), Val (TupV range), Val (TupV range')] =
  Val $ FloatV $ scaleLinear x range range'

pathFromPoints :: ConstCompFn
pathFromPoints [Val (PtListV pts)] =
  let path = Open $ map Pt pts
  in Val $ PathDataV [path]

joinPath :: ConstCompFn
joinPath [Val (PtListV pq), Val (PtListV qr), Val (PtListV rp)] =
  let path = Closed $ map Pt $ pq ++ qr ++ rp
  in Val $ PathDataV [path]

--------------------------------------------------------------------------------
-- Objective Functions
near :: ObjFn
near [GPI o, Val (FloatV x), Val (FloatV y)] = distsq (getX o, getY o) (x, y)
near [GPI o1, GPI o2] = distsq (getX o1, getY o1) (getX o2, getY o2)
near [GPI o1, GPI o2, Val (FloatV offset)] =
  distsq (getX o1, getY o1) (getX o2, getY o2) - offset ^ 2
near [GPI img@("Image", _), GPI lab@("Text", _), Val (FloatV xoff), Val (FloatV yoff)] =
  let center = (getNum img "centerX", getNum img "centerY")
      offset = (xoff, yoff)
  in distsq (getX lab, getY lab) (center `plus2` offset)
  where
    plus2 (a, b) (c, d) = (a + c, b + d)

center :: ObjFn
center [GPI o] = tr "center: " $ distsq (getX o, getY o) (0, 0)

centerX :: ObjFn
centerX [Val (FloatV x)] = tr "centerX" $ x ^ 2

-- | 'sameCenter' encourages two objects to center at the same point
sameCenter :: ObjFn
sameCenter [GPI a, GPI b] = (getX a - getX b) ^ 2 + (getY a - getY b) ^ 2

centerLabel :: ObjFn
centerLabel [a, b, Val (FloatV w)] = w * centerLabel [a, b] -- TODO factor out
-- TODO revert
-- centerLabel [GPI curve, GPI text]
--     | curve `is` "Curve" && text `is` "Text" =
--         let ((lx, ly), (rx, ry)) = bezierBbox curve
--             (xmargin, ymargin) = (-10, 30)
--             midbez = ((lx + rx) / 2 + xmargin, (ly + ry) / 2 + ymargin) in
--         distsq midbez (getX text, getY text)
centerLabel [GPI p, GPI l]
  | p `is` "AnchorPoint" && l `is` "Text" =
    let [px, py, lx, ly] = [getX p, getY p, getX l, getY l]
    in (px + 10 - lx) ^ 2 + (py + 20 - ly) ^ 2 -- Top right from the point
-- -- TODO: depends on orientation of arrow
centerLabel [GPI arr, GPI text]
  | ((arr `is` "Arrow") || (arr `is` "Line")) && text `is` "Text" =
    let (sx, sy, ex, ey) =
          ( getNum arr "startX"
          , getNum arr "startY"
          , getNum arr "endX"
          , getNum arr "endY")
        (mx, my) = midpoint (sx, sy) (ex, ey)
        (lx, ly) = (getX text, getY text)
    in (mx - lx) ^ 2 + (my + 1.1 * getNum text "h" - ly) ^ 2 -- Top right from the point
centerLabel [a, b] = sameCenter [a, b]
                -- (mx - lx)^2 + (my + 1.1 * hl' l - ly)^2 -- Top right from the point

-- centerLabel [CB' a, L' l] [mag] = -- use the float input?
--                 let (sx, sy, ex, ey) = (startx' a, starty' a, endx' a, endy' a)
--                     (mx, my) = midpoint (sx, sy) (ex, ey)
--                     (lx, ly) = (xl' l, yl' l) in
-- | `centerArrow` positions an arrow between two objects, with some spacing
centerArrow :: ObjFn
centerArrow [GPI arr@("Arrow", _), GPI sq1@("Square", _), GPI sq2@("Square", _)] =
  _centerArrow
    arr
    [getX sq1, getY sq1]
    [getX sq2, getY sq2]
    [ spacing + (halfDiagonal . flip getNum "side") sq1
    , negate $ spacing + (halfDiagonal . flip getNum "side") sq2
    ]
centerArrow [GPI arr@("Arrow", _), GPI sq@("Square", _), GPI circ@("Circle", _)] =
  _centerArrow
    arr
    [getX sq, getY sq]
    [getX circ, getY circ]
    [ spacing + (halfDiagonal . flip getNum "side") sq
    , negate $ spacing + getNum circ "radius"
    ]
centerArrow [GPI arr@("Arrow", _), GPI circ@("Circle", _), GPI sq@("Square", _)] =
  _centerArrow
    arr
    [getX circ, getY circ]
    [getX sq, getY sq]
    [ spacing + getNum circ "radius"
    , negate $ spacing + (halfDiagonal . flip getNum "side") sq
    ]
centerArrow [GPI arr@("Arrow", _), GPI circ1@("Circle", _), GPI circ2@("Circle", _)] =
  _centerArrow
    arr
    [getX circ1, getY circ1]
    [getX circ2, getY circ2]
    [spacing * getNum circ1 "r", negate $ spacing * getNum circ2 "r"]
centerArrow [GPI arr@("Arrow", _), GPI ell1@("Ellipse", _), GPI ell2@("Ellipse", _)] =
  _centerArrow
    arr
    [getX ell1, getY ell1]
    [getX ell2, getY ell2]
    [spacing * getNum ell1 "radius1", negate $ spacing * getNum ell2 "radius2"]
                -- FIXME: inaccurate, only works for horizontal cases
centerArrow [GPI arr@("Arrow", _), GPI pt1@("AnchorPoint", _), GPI pt2@("AnchorPoint", _)] =
  _centerArrow
    arr
    [getX pt1, getY pt1]
    [getX pt2, getY pt2]
    [spacing * 2 * r2f ptRadius, negate $ spacing * 2 * r2f ptRadius]
                -- FIXME: anchor points have no radius
centerArrow [GPI arr@("Arrow", _), GPI text1@("Text", _), GPI text2@("Text", _)] =
  _centerArrow
    arr
    [getX text1, getY text1]
    [getX text2, getY text2]
    [spacing * getNum text1 "h", negate $ 2 * spacing * getNum text2 "h"]
centerArrow [GPI arr@("Arrow", _), GPI text@("Text", _), GPI circ@("Circle", _)] =
  _centerArrow
    arr
    [getX text, getY text]
    [getX circ, getY circ]
    [1.5 * getNum text "w", negate $ spacing * getNum circ "radius"]

spacing :: (Autofloat a) => a
spacing = 1.1 -- TODO: arbitrary

_centerArrow :: Autofloat a => Shape a -> [a] -> [a] -> [a] -> a
_centerArrow arr@("Arrow", _) s1@[x1, y1] s2@[x2, y2] [o1, o2] =
  let vec = [x2 - x1, y2 - y1] -- direction the arrow should point to
      dir = normalize vec
      [sx, sy, ex, ey] =
        if norm vec > o1 + abs o2
          then (s1 +. o1 *. dir) ++ (s2 +. o2 *. dir)
          else s1 ++ s2
      [fromx, fromy, tox, toy] =
        [ getNum arr "startX"
        , getNum arr "startY"
        , getNum arr "endX"
        , getNum arr "endY"
        ]
  in (fromx - sx) ^ 2 + (fromy - sy) ^ 2 + (tox - ex) ^ 2 + (toy - ey) ^ 2

-- | 'repel' exert an repelling force between objects
-- TODO: temporarily written in a generic way
-- Note: repel's energies are quite small so the function is scaled by repelWeight before being applied
repel :: ObjFn
repel [Val (TupV x), Val (TupV y)] = 1 / (distsq x y + epsd)
repel [GPI a, GPI b] = 1 / (distsq (getX a, getY a) (getX b, getY b) + epsd)
repel [GPI a, GPI b, Val (FloatV weight)] =
  weight / (distsq (getX a, getY a) (getX b, getY b) + epsd)
    -- trace ("REPEL: " ++ show a ++ "\n" ++ show b ++ "\n" ++ show res) res

-- repel [C' c, S' d] [] = 1 / distsq (xc' c, yc' c) (xs' d, ys' d) - r' c - side' d + epsd
-- repel [S' c, C' d] [] = 1 / distsq (xc' d, yc' d) (xs' c, ys' c) - r' d - side' c + epsd
-- repel [P' c, P' d] [] = if c == d then 0 else 1 / distsq (xp' c, yp' c) (xp' d, yp' d) - 2 * r2f ptRadius + epsd
-- repel [L' c, L' d] [] = if c == d then 0 else 1 / distsq (xl' c, yl' c) (xl' d, yl' d)
-- repel [L' c, C' d] [] = 1 / distsq (xl' c, yl' c) (xc' d, yc' d)
-- repel [C' c, L' d] [] = 1 / distsq (xc' c, yc' c) (xl' d, yl' d)
-- repel [L' c, S' d] [] = 1 / distsq (xl' c, yl' c) (xs' d, ys' d)
-- repel [S' c, L' d] [] = 1 / distsq (xs' c, ys' c) (xl' d, yl' d)
-- repel [A' c, L' d] [] = repel' (startx' c, starty' c) (xl' d, yl' d) +
--         repel' (endx' c, endy' c) (xl' d, yl' d)
-- repel [A' c, C' d] [] = repel' (startx' c, starty' c) (xc' d, yc' d) +
--         repel' (endx' c, endy' c) (xc' d, yc' d)
-- repel [IM' c, IM' d] [] = 1 / (distsq (xim' c, yim' c) (xim' d, yim' d) + epsd) - sizeXim' c - sizeXim' d --TODO Lily check this math is correct
-- repel [a, b] [] = if a == b then 0 else 1 / (distsq (getX a, getY a) (getX b, getY b) )
topRightOf :: ObjFn
topRightOf [GPI l@("Text", _), GPI s@("Square", _)] =
  dist
    (getX l, getY l)
    (getX s + 0.5 * getNum s "side", getY s + 0.5 * getNum s "side")
topRightOf [GPI l@("Text", _), GPI s@("Rectangle", _)] =
  dist
    (getX l, getY l)
    (getX s + 0.5 * getNum s "sizeX", getY s + 0.5 * getNum s "sizeY")

topLeftOf :: ObjFn
topLeftOf [GPI l@("Text", _), GPI s@("Square", _)] =
  dist
    (getX l, getY l)
    (getX s - 0.5 * getNum s "side", getY s - 0.5 * getNum s "side")
topLeftOf [GPI l@("Text", _), GPI s@("Rectangle", _)] =
  dist
    (getX l, getY l)
    (getX s - 0.5 * getNum s "sizeX", getY s - 0.5 * getNum s "sizeY")

nearHead :: ObjFn
nearHead [GPI l, GPI lab@("Text", _), Val (FloatV xoff), Val (FloatV yoff)] =
  if linelike l
    then let end = (getNum l "endX", getNum l "endY")
             offset = (xoff, yoff)
         in distsq (getX lab, getY lab) (end `plus2` offset)
    else error "GPI type for nearHead must be line-like"
  where
    plus2 (a, b) (c, d) = (a + c, b + d)

nearEndVert :: ObjFn
-- expects a vertical line
nearEndVert [GPI line@("Line", _), GPI lab@("Text", _)] =
  let (sx, sy, ex, ey) = linePts line
  in let bottompt =
           if sy < ey
             then (sx, sy)
             else (ex, ey)
     in let yoffset = -25
        in let res =
                 distsq
                   (getX lab, getY lab)
                   (fst bottompt, snd bottompt + yoffset)
           in res

nearEndHoriz :: ObjFn
-- expects a horiz line
nearEndHoriz [GPI line@("Line", _), GPI lab@("Text", _)] =
  let (sx, sy, ex, ey) = linePts line
  in let leftpt =
           if sx < ex
             then (sx, sy)
             else (ex, ey)
     in let xoffset = -25
        in distsq (getX lab, getY lab) (fst leftpt + xoffset, snd leftpt)

-- | 'above' makes sure the first argument is on top of the second.
above :: ObjFn
above [GPI top, GPI bottom, Val (FloatV offset)] =
  (getY top - getY bottom - offset) ^ 2
above [GPI top, GPI bottom] = (getY top - getY bottom - 100) ^ 2

-- | 'sameHeight' forces two objects to stay at the same height (have the same Y value)
sameHeight :: ObjFn
sameHeight [GPI a, GPI b] = (getY a - getY b) ^ 2

equal :: ObjFn
equal [Val (FloatV a), Val (FloatV b)] = (a - b) ^ 2

distBetween :: ObjFn
distBetween [GPI c1@("Circle", _), GPI c2@("Circle", _), Val (FloatV padding)] =
  let (r1, r2, x1, y1, x2, y2) =
        (getNum c1 "r", getNum c2 "r", getX c1, getY c1, getX c2, getY c2)
    -- If one's a subset of another or has same radius as other
    -- If they only intersect
  in if dist (x1, y1) (x2, y2) < (r1 + r2)
       then repel [GPI c1, GPI c2, Val (FloatV repelWeight)] -- 1 / distsq (x1, y1) (x2, y2)
    -- If they don't intersect
         -- trace ("padding: " ++ show padding)
       else (dist (x1, y1) (x2, y2) - r1 - r2 - padding) ^ 2

--------------------------------------------------------------------------------
-- Constraint Functions
at :: ConstrFn
at [GPI o, Val (FloatV x), Val (FloatV y)] = (getX o - x) ^ 2 + (getY o - y) ^ 2

lessThan :: ConstrFn
lessThan [Val (FloatV x), Val (FloatV y)] = x - y

contains :: ConstrFn
contains [GPI o1@("Circle", _), GPI o2@("Circle", _)] =
  dist (getX o1, getY o1) (getX o2, getY o2) - (getNum o1 "r" - getNum o2 "r")
contains [GPI outc@("Circle", _), GPI inc@("Circle", _), Val (FloatV padding)] =
  dist (getX outc, getY outc) (getX inc, getY inc) -
  (getNum outc "r" - padding - getNum inc "r")
contains [GPI c@("Circle", _), GPI rect@("Rectangle", _)] =
  let (x, y, w, h) =
        (getX rect, getY rect, getNum rect "sizeX", getNum rect "sizeY")
      [x0, x1, y0, y1] = [x - w / 2, x + w / 2, y - h / 2, y + h / 2]
      pts = [(x0, y0), (x0, y1), (x1, y0), (x1, y1)]
      (cx, cy, radius) = (getX c, getY c, getNum c "r")
  in sum $ map (\(a, b) -> max 0 $ dist (cx, cy) (a, b) - radius) pts
contains [GPI c@("Circle", _), GPI t@("Text", _)] =
  let res =
        dist (getX t, getY t) (getX c, getY c) - getNum c "r" +
        max (getNum t "w") (getNum t "h")
  in if res < 0
       then 0
       else res
    -- TODO: factor out the vertex access code to a high-level getter
    -- NOTE: seems that the following version doesn't perform as well as the hackier old version. Maybe it's the shape of the obj that is doing it, but we do observe that the labels tend to get really close to the edges
    -- let (x, y, w, h)     = (getX t, getY t, getNum t "w", getNum t "h")
    --     [x0, x1, y0, y1] = [x - w/2, x + w/2, y - h/2, y + h/2]
    --     pts              = [(x0, y0), (x0, y1), (x1, y0), (x1, y1)]
    --     (cx, cy, radius) = (getX c, getY c, getNum c "r")
    -- in sum $ map (\(a, b) -> (max 0 $ dist (cx, cy) (a, b) - radius)^2) pts
contains [GPI s@("Square", _), GPI l@("Text", _)] =
  dist (getX l, getY l) (getX s, getY s) - getNum s "side" / 2 +
  getNum l "w" / 2
contains [GPI s@("Rectangle", _), GPI l@("Text", _)]
    -- TODO: implement precisely, max (w, h)? How about diagonal case?
 =
  dist (getX l, getY l) (getX s, getY s) - getNum s "sizeX" / 2 +
  getNum l "w" / 2
contains [GPI outc@("Square", _), GPI inc@("Square", _)] =
  dist (getX outc, getY outc) (getX inc, getY inc) -
  (0.5 * getNum outc "side" - 0.5 * getNum inc "side")
contains [GPI outc@("Square", _), GPI inc@("Circle", _)] =
  dist (getX outc, getY outc) (getX inc, getY inc) -
  (0.5 * getNum outc "side" - getNum inc "r")
contains [GPI outc@("Square", _), GPI inc@("Circle", _), Val (FloatV padding)] =
  dist (getX outc, getY outc) (getX inc, getY inc) -
  (0.5 * getNum outc "side" - padding - getNum inc "r")
contains [GPI outc@("Circle", _), GPI inc@("Square", _)] =
  dist (getX outc, getY outc) (getX inc, getY inc) -
  (getNum outc "r" - 0.5 * getNum inc "side")
contains [GPI set@("Ellipse", _), GPI label@("Text", _)] =
  dist (getX label, getY label) (getX set, getY set) -
  max (getNum set "r") (getNum set "r") +
  getNum label "w"
contains [GPI sq@("Square", _), GPI ar@("Arrow", _)] =
  let (startX, startY, endX, endY) = arrowPts ar
      (x, y) = (getX sq, getY sq)
      side = getNum sq "side"
      (lx, ly) = ((x - side / 2) * 0.75, (y - side / 2) * 0.75)
      (rx, ry) = ((x + side / 2) * 0.75, (y + side / 2) * 0.75)
  in inRange startX lx rx + inRange startY ly ry + inRange endX lx rx +
     inRange endY ly ry
contains [GPI rt@("Rectangle", _), GPI ar@("Arrow", _)] =
  let (startX, startY, endX, endY) = arrowPts ar
      (x, y) = (getX rt, getY rt)
      (w, h) = (getNum rt "sizeX", getNum rt "sizeY")
      (lx, ly) = (x - w / 2, y - h / 2)
      (rx, ry) = (x + w / 2, y + h / 2)
  in inRange startX lx rx + inRange startY ly ry + inRange endX lx rx +
     inRange endY ly ry

inRange a l r
  | a < l = (a - l) ^ 2
  | a > r = (a - r) ^ 2
  | otherwise = 0

inRange'' :: (Autofloat a) => a -> a -> a -> a
inRange'' v left right
  | v < left = left - v
  | v > right = v - right
  | otherwise = 0

inRange' :: ConstrFn
inRange' [Val (FloatV v), Val (FloatV left), Val (FloatV right)]
  | v < left = left - v
  | v > right = v - right
  | otherwise = 0

-- = inRange v left right
onCanvas :: ConstrFn
onCanvas [GPI g] =
  let (leftX, rightX) = (-canvasHeight / 2, canvasHeight / 2)
      (leftY, rightY) = (-canvasWidth / 2, canvasWidth / 2)
  in inRange'' (getX g) (r2f leftX) (r2f rightX) +
     inRange'' (getY g) (r2f leftY) (r2f rightY)

unit' :: ConstrFn
unit' [Val (ListV vec)] = hasNorm [Val (ListV vec), Val (FloatV 1)]

-- | This is an equality constraint (x = c) via two inequality constraints (x <= c and x >= c)
hasNorm :: ConstrFn
hasNorm [Val (ListV vec), Val (FloatV desired_norm)] =
  let norms = (norm vec, desired_norm) -- TODO: Use normal norm or normsq?
      (norm_max, norm_min) = (uncurry max norms, uncurry min norms)
  in norm_max - norm_min

-- contains [GPI set@("Circle", _), P' GPI pt@("", _)] = dist (getX pt, getX pt) (getX set, getY set) - 0.5 * r' set
-- TODO: only approx
-- contains [S' GPI set@("", _), P' GPI pt@("", _)] =
--     dist (getX pt, getX pt) (getX set, getX set) - 0.4 * side' set
-- FIXME: doesn't work
-- contains [E' GPI set@("", _), P' GPI pt@("", _)] =
--     dist (getX pt, getX pt) (xe' set, getX set) - max (rx' set) (ry' set) * 0.9
-- NOTE/HACK: all objects will have min/max size attached, but not all of them are implemented
maxSize :: ConstrFn
-- TODO: why do we need `r2f` now? Didn't have to before
limit = max canvasWidth canvasHeight

maxSize [GPI c@("Circle", _)] = getNum c "r" - r2f (limit / 6)
maxSize [GPI s@("Square", _)] = getNum s "side" - r2f (limit / 3)
maxSize [GPI r@("Rectangle", _)] =
  let max_side = max (getNum r "sizeX") (getNum r "sizeY")
  in max_side - r2f (limit / 3)
maxSize [GPI im@("Image", _)] =
  let max_side = max (getNum im "lengthX") (getNum im "lengthY")
  in max_side - r2f (limit / 3)
maxSize [GPI e@("Ellipse", _)] =
  max (getNum e "r") (getNum e "r") - r2f (limit / 3)
maxSize _ = 0

-- NOTE/HACK: all objects will have min/max size attached, but not all of them are implemented
minSize :: ConstrFn
minSize [GPI c@("Circle", _)] = 20 - getNum c "r"
minSize [GPI s@("Square", _)] = 20 - getNum s "side"
minSize [GPI r@("Rectangle", _)] =
  let min_side = min (getNum r "sizeX") (getNum r "sizeY")
  in 20 - min_side
minSize [GPI e@("Ellipse", _)] = 20 - min (getNum e "r") (getNum e "r")
minSize [GPI g] =
  if fst g == "Line" || fst g == "Arrow"
    then let vec =
               [ getNum g "endX" - getNum g "startX"
               , getNum g "endY" - getNum g "startY"
               ]
         in 50 - norm vec
    else 0
minSize [GPI g, Val (FloatV len)] =
  if fst g == "Line" || fst g == "Arrow"
    then let vec =
               [ getNum g "endX" - getNum g "startX"
               , getNum g "endY" - getNum g "startY"
               ]
         in len - norm vec
    else 0

smallerThan :: ConstrFn
smallerThan [GPI inc@("Circle", _), GPI outc@("Circle", _)] =
  getNum inc "r" - getNum outc "r" - 0.4 * getNum outc "r" -- TODO: taking this as a parameter?
smallerThan [GPI inc@("Circle", _), GPI outs@("Square", _)] =
  0.5 * getNum outs "side" - getNum inc "r"
smallerThan [GPI ins@("Square", _), GPI outc@("Circle", _)] =
  halfDiagonal $ getNum ins "side" - getNum outc "r"
smallerThan [GPI ins@("Square", _), GPI outs@("Square", _)] =
  getNum ins "side" - getNum outs "side" - subsetSizeDiff

outsideOf :: ConstrFn
outsideOf [GPI l@("Text", _), GPI c@("Circle", _)] =
  let padding = 10.0
  in let labelR = max (getNum l "w") (getNum l "h")
     in -dist (getX l, getY l) (getX c, getY c) + getNum c "r" + labelR +
        padding
-- TODO: factor out runtime weights
outsideOf [GPI l@("Text", _), GPI c@("Circle", _), Val (FloatV weight)] =
  weight * outsideOf [GPI l, GPI c]

overlapping :: ConstrFn
overlapping [GPI xset@("Circle", _), GPI yset@("Circle", _)] =
  looseIntersect
    [ [getX xset, getY xset, getNum xset "r"]
    , [getX yset, getY yset, getNum yset "r"]
    ]
overlapping [GPI xset@("Square", _), GPI yset@("Circle", _)] =
  looseIntersect
    [ [getX xset, getY xset, 0.5 * getNum xset "side"]
    , [getX yset, getY yset, getNum yset "r"]
    ]
overlapping [GPI xset@("Circle", _), GPI yset@("Square", _)] =
  looseIntersect
    [ [getX xset, getY xset, getNum xset "r"]
    , [getX yset, getY yset, 0.5 * getNum yset "side"]
    ]
overlapping [GPI xset@("Square", _), GPI yset@("Square", _)] =
  looseIntersect
    [ [getX xset, getY xset, 0.5 * getNum xset "side"]
    , [getX yset, getY yset, 0.5 * getNum yset "side"]
    ]

looseIntersect :: (Autofloat a) => [[a]] -> a
looseIntersect [[x1, y1, s1], [x2, y2, s2]] =
  dist (x1, y1) (x2, y2) - (s1 + s2 - 10)

disjoint :: ConstrFn
disjoint [GPI xset@("Circle", _), GPI yset@("Circle", _)] =
  noIntersect
    [ [getX xset, getY xset, getNum xset "r"]
    , [getX yset, getY yset, getNum yset "r"]
    ]
-- This is not totally correct since it doesn't account for the diagonal of a square
disjoint [GPI xset@("Square", _), GPI yset@("Square", _)] =
  noIntersect
    [ [getX xset, getY xset, 0.5 * getNum xset "side"]
    , [getX yset, getY yset, 0.5 * getNum yset "side"]
    ]
disjoint [GPI xset@("Rectangle", _), GPI yset@("Rectangle", _), Val (FloatV offset)]
    -- Arbitrarily using x size
 =
  noIntersectOffset
    [ [getX xset, getY xset, 0.5 * getNum xset "sizeX"]
    , [getX yset, getY yset, 0.5 * getNum yset "sizeX"]
    ]
    offset
disjoint [GPI box@("Text", _), GPI seg@("Line", _), Val (FloatV offset)] =
  let center = (getX box, getY box)
      (v, w) = (getPoint "start" seg, getPoint "end" seg)
      cp = closestpt_pt_seg center (v, w)
      len_approx = getNum box "w" / 2.0 -- TODO make this more exact
  in -(dist center cp) + len_approx + offset
    -- i.e. dist from center of box to closest pt on line seg is greater than the approx distance between the box center and the line + some offset
-- For horizontally collinear line segments only
-- with endpoints (si, ei), assuming si < ei (e.g. enforced by some other constraint)
-- Make sure the closest endpoints are separated by some padding
disjoint [GPI o1, GPI o2] =
  if linelike o1 && linelike o2
    then let (start1, end1, start2, end2) =
               ( fst $ getPoint "start" o1
               , fst $ getPoint "end" o1
               , fst $ getPoint "start" o2
               , fst $ getPoint "end" o2 -- Throw away y coords
                )
             padding = 30 -- should be > 0
            -- Six cases for two intervals: disjoint [-] (-), overlap (-[-)-], contained [-(-)-], and swapping the intervals
            -- Assuming si < ei, we can just push away the closest start and end of the two intervals
             distA = unsignedDist end1 start2
             distB = unsignedDist end2 start1
         in if distA <= distB
              then end1 + padding - start2 -- Intervals separated by padding (original condition: e1 + c < s2)
              else end2 + padding - start1 -- e2 + c < s1
    else error "expected two linelike GPIs in `disjoint`"
  where
    unsignedDist :: (Autofloat a) => a -> a -> a
    unsignedDist x y = abs $ x - y

-- exterior point method constraint: no intersection (meaning also no subset)
noIntersect :: (Autofloat a) => [[a]] -> a
noIntersect [[x1, y1, s1], [x2, y2, s2]] =
  -(dist (x1, y1) (x2, y2)) + s1 + s2 + offset
  where
    offset = 10

noIntersectOffset :: (Autofloat a) => [[a]] -> a -> a
noIntersectOffset [[x1, y1, s1], [x2, y2, s2]] offset =
  -(dist (x1, y1) (x2, y2)) + s1 + s2 + offset

--------------------------------------------------------------------------------
-- Wrappers for transforms and operations to call from Style
-- NOTE: Haskell trig is in radians
rotate :: ConstCompFn
rotate [Val (FloatV radians)] = Val $ HMatrixV $ rotationM radians

rotateAbout :: ConstCompFn
rotateAbout [Val (FloatV angle), Val (FloatV x), Val (FloatV y)] =
  Val $ HMatrixV $ rotationAboutM angle (x, y)

translate :: ConstCompFn
translate [Val (FloatV x), Val (FloatV y)] =
  Val $ HMatrixV $ translationM (x, y)

scale :: ConstCompFn
scale [Val (FloatV cx), Val (FloatV cy)] = Val $ HMatrixV $ scalingM (cx, cy)

-- Apply transforms from left to right order: do t2, then t1
andThen :: ConstCompFn
andThen [Val (HMatrixV t2), Val (HMatrixV t1)] =
  Val $ HMatrixV $ composeTransform t1 t2

------ Sample shapes
-- TODO: parse lists of 2-tuples
mkPoly :: ConstCompFn
mkPoly [Val (FloatV x1), Val (FloatV x2), Val (FloatV x3), Val (FloatV x4), Val (FloatV x5), Val (FloatV x6)] =
  Val $ PtListV [(x1, x2), (x3, x4), (x5, x6)]
mkPoly [Val (FloatV x1), Val (FloatV x2), Val (FloatV x3), Val (FloatV x4), Val (FloatV x5), Val (FloatV x6), Val (FloatV x7), Val (FloatV x8)] =
  Val $ PtListV [(x1, x2), (x3, x4), (x5, x6), (x7, x8)]
mkPoly [Val (FloatV x1), Val (FloatV x2), Val (FloatV x3), Val (FloatV x4), Val (FloatV x5), Val (FloatV x6), Val (FloatV x7), Val (FloatV x8), Val (FloatV x9), Val (FloatV x10)] =
  Val $ PtListV [(x1, x2), (x3, x4), (x5, x6), (x7, x8), (x9, x10)]

unitSquare :: ConstCompFn
unitSquare [] = Val $ PtListV unitSq

unitCircle :: ConstCompFn
unitCircle [] = Val $ PtListV $ circlePoly 1.0 --unitCirc

testTri :: ConstCompFn
testTri [] = Val $ PtListV testTriangle

testNonconvexPoly :: ConstCompFn
testNonconvexPoly [] = Val $ PtListV testNonconvex

-- No guarantees about nonintersection, convexity, etc. Just a bunch of points in a range.
randomPolygon :: CompFn
randomPolygon [Val (IntV n)] g =
  let range = (-100, 100)
      (xs, g') = randomsIn g n range
      (ys, g'') = randomsIn g' n range
      pts = zip xs ys
  in (Val $ PtListV pts, g'')

------ Transform objectives and constraints
-- Optimize directly on the transform
-- this function is only a demo
nearT :: ObjFn
nearT [GPI o, Val (FloatV x), Val (FloatV y)] =
  let tf = getTransform o
  in distsq (dx tf, dy tf) (x, y)

boundaryIntersect :: ObjFn
boundaryIntersect [GPI o1, GPI o2] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in dsqGG p1 p2

containsPoly :: ObjFn
containsPoly [GPI o1, GPI o2] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eAcontainB p1 p2

disjointPoly :: ObjFn
disjointPoly [GPI o1, GPI o2] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eABdisj p1 p2

-- pad / padding: minimum amt of separation between two shapes' boundaries.
-- See more at energy definitions (eBinAPad, eBoutAPad, ePad, etc.)
containsPolyPad :: ObjFn
containsPolyPad [GPI o1, GPI o2, Val (FloatV ofs)] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eBinAPad p1 p2 ofs

disjointPolyPad :: ObjFn
disjointPolyPad [GPI o1, GPI o2, Val (FloatV ofs)] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eBoutAPad p1 p2 ofs

padding :: ObjFn
padding [GPI o1, GPI o2, Val (FloatV ofs)] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in ePad p1 p2 ofs

containAndTangent :: ObjFn
containAndTangent [GPI o1, GPI o2] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in (eAcontainB p1 p2) + (dsqGG p1 p2)

disjointAndTangent :: ObjFn
disjointAndTangent [GPI o1, GPI o2] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in (eABdisj p1 p2) + (dsqGG p1 p2)

-- ofs / offset: exact amt of separation between two shapes' boundaries.
-- See more at energy definitions (eBinAOffs, eBoutAOffs, eOffs, etc.)
containsPolyOfs :: ObjFn
containsPolyOfs [GPI o1, GPI o2, Val (FloatV ofs)] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eBinAOffs p1 p2 ofs

disjointPolyOfs :: ObjFn
disjointPolyOfs [GPI o1, GPI o2, Val (FloatV ofs)] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eBoutAOffs p1 p2 ofs

polyOnCanvas :: ObjFn
polyOnCanvas [GPI o] =
  let (halfw, halfh) = (r2f canvasWidth / 2, r2f canvasHeight / 2)
      canv =
        [(-halfw, -halfh), (halfw, -halfh), (halfw, halfh), (-halfw, halfh)]
  in eBinAPad (toPoly canv) (getPolygon o) 0

maximumSize :: ObjFn
maximumSize [GPI o, Val (FloatV s)] = eMaxSize (getPolygon o) s

minimumSize :: ObjFn
minimumSize [GPI o, Val (FloatV s)] = eMinSize (getPolygon o) s

-- inputs: shape, p.x, p.y, target.x, target.y,
-- where p is some point in local coordinates of shape (ex: (0,0) is the center for most shapes),
-- and target is some coordinates on canvas (ex: (0,0) is the origin).
-- Encourages transformation to shape so that p is at the location of target.
atPoint :: ObjFn
atPoint [GPI o, Val (FloatV ox), Val (FloatV oy), Val (FloatV x), Val (FloatV y)] =
  let tf = getTransformation o
  in dsqPP (x, y) $ tf ## (ox, oy)

-- inputs: shape1, p1.x, p1.y, shape2, p2.x, p2.y,
-- where p1 is some point in local coordinates of shape1 (ex: (0,0) is the center for most shapes)
-- and p2 is some point in local coordinates of shape2.
-- Encourages transformation to both shapes so that p1 and p2 overlap.
atPoint2 :: ObjFn
atPoint2 [GPI o1, Val (FloatV x1), Val (FloatV y1), GPI o2, Val (FloatV x2), Val (FloatV y2)] =
  let tf1 = getTransformation o1
      tf2 = getTransformation o2
  in dsqPP (tf1 ## (x1, y1)) (tf2 ## (x2, y2))

-- inputs: shape, target.x, target.y, offset,
-- where target is some coordinates on canvas (ex: (0,0) is the origin).
-- Encourages transformation to shape so that its boundary becomes offset pixels away from target.
-- Could have many other versions of "near".
nearPoint :: ObjFn
nearPoint [GPI o, Val (FloatV x), Val (FloatV y), Val (FloatV ofs)]
      -- tf = getTransformation o
 =
  let
  in eOffsP (getPolygon o) (x, y) ofs

-- inputs: shape1, p1.x, p1.y, shape2, p2.x, p2.y, offset,
-- where p1 is some point in local coordinates of shape1 (ex: (0,0) is the center for most shapes)
-- and p2 is some point in local coordinates of shape2.
-- Encourages transformation to both shapes so that p1 and p2 are offset pixels apart.
nearPoint2 :: ObjFn
nearPoint2 [GPI o1, Val (FloatV x1), Val (FloatV y1), GPI o2, Val (FloatV x2), Val (FloatV y2), Val (FloatV ofs)] =
  let tf1 = getTransformation o1
      tf2 = getTransformation o2
  in eOffsPP (tf1 ## (x1, y1)) (tf2 ## (x2, y2)) ofs

sameSize :: ObjFn
sameSize [GPI o1, GPI o2] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eSameSize p1 p2

smaller :: ObjFn
smaller [GPI o1, GPI o2] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eSmallerThan p1 p2

-- alignment and ordering: use center of bbox to represent input shapes, and align/order them
-- See more at functions alignPPA and orderPPA
alignAlong :: ObjFn
alignAlong [GPI o1, GPI o2, Val (FloatV angleInDegrees)] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eAlign p1 p2 angleInDegrees

orderAlong :: ObjFn
orderAlong [GPI o1, GPI o2, Val (FloatV angleInDegrees)] =
  let (p1, p2) = (getPolygon o1, getPolygon o2)
  in eOrder p1 p2 angleInDegrees

transformSRT :: ConstCompFn
transformSRT [Val (FloatV sx), Val (FloatV sy), Val (FloatV theta), Val (FloatV dx), Val (FloatV dy)] =
  Val $ HMatrixV $ paramsToMatrix (sx, sy, theta, dx, dy)

--------------------------------------------------------------------------------
-- Default functions for every shape
defaultConstrsOf :: ShapeTypeStr -> [FuncName]
defaultConstrsOf "Text"  = []
defaultConstrsOf "Curve" = []
-- defaultConstrsOf "Line" = []
defaultConstrsOf _       = [] -- [ "minSize", "maxSize" ]
                 -- TODO: remove? these fns make the optimization too hard to solve sometimes

defaultObjFnsOf :: ShapeTypeStr -> [FuncName]
defaultObjFnsOf _ = [] -- NOTE: not used yet

--------------------------------------------------------------------------------
-- Errors
noFunctionError n = error ("Cannot find function \"" ++ n ++ "\"")

noSignatureError n =
  error ("Cannot find signatures defined for function \"" ++ n ++ "\"")

sigMismatchError n sig argTypes =
  error
    ("Invalid arguments for function \"" ++
     n ++
     "\". Passed in:\n" ++
     show argTypes ++ "\nPredefined signature is: " ++ show sig)

noMatchedSigError n sigs argTypes =
  error
    ("Cannot find matching signatures defined for function \"" ++
     n ++
     "\". Passed in:\n" ++
     show argTypes ++ "\nPossible signatures are: " ++ sigStrs)
  where
    sigStrs = concatMap ((++ "\n") . show) sigs