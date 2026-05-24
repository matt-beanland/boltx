<!--
SPDX-FileCopyrightText: 2024 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

## Unreleased

* 32 `%Bolty.Types.Point{}` parameters are now sent as native PackStream
  Points instead of being silently converted to Maps. This allows Points
  (and arrays of Points) to be stored directly as Neo4j node properties.
  **Breaking:** callers that pass a `%Bolty.Types.Point{}` to Cypher's
  `point()` constructor must now pass a Map instead (or use
  `Bolty.Types.Point.format_param/1` to convert). See
  https://github.com/diffo-dev/bolty/pull/<TODO>.

## v0.0.12

* 25 Execute/4 sends send_reset for :syntax_error/:semantic_error when inside a transaction
@matt-beanland in https://github.com/diffo-dev/bolty/pull/26
* 27 additional bolty issues with transactions 
@matt-beanland in https://github.com/diffo-dev/bolty/pull/28
* 24 Unknown Error (CaseClauseError) no case clause matching : {:ignored, [0, 0]}
@matt-beanland in https://github.com/diffo-dev/bolty/pull/29

**Full Changelog**: https://github.com/diffo-dev/bolty/compare/0.0.11...0.0.12

## v0.0.11

## What's Changed
* fix UndefinedFunctionError when formatting a Neo4j EntityNotFound error by @matt-beanland in https://github.com/diffo-dev/bolty/pull/21

**Full Changelog**: https://github.com/diffo-dev/bolty/compare/0.0.10...0.0.11

## v0.0.10

## What's Changed
* 10 datetime param illegal by @matt-beanland in https://github.com/diffo-dev/bolty/pull/14

**Full Changelog**: https://github.com/diffo-dev/bolty/compare/0.0.9...0.0.10

## v0.0.9
  * fix duration stored as string
  
## v0.0.8
  * fix duration microseconds

## v0.0.7 
  * initial version from boltx v0.0.6
  * duration
  * maintenance
  * negotiate range