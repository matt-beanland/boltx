# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule BoltyTest do
  use ExUnit.Case, async: true

  alias Bolty.Response
  alias Bolty.Types.{Point, DateTimeWithTZOffset, TimeWithTZOffset}

  alias Bolty.TypesHelper

  @opts Bolty.TestHelper.opts()

  defmodule TestUser do
    defstruct name: "", bolty: true, half_life: nil
  end

  describe "connect" do
    @tag :core
    test "connect using default protocol" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn} = Bolty.start_link(opts)
      Bolty.query!(conn, "RETURN 1024 AS a")
    end
  end

  describe "query" do
    setup [:connect, :truncate, :rebuild_fixtures]

    @tag :core
    test "a simple query", c do
      response = Bolty.query!(c.conn, "RETURN 300 AS r")

      assert %Response{results: [%{"r" => 300}]} = response
      assert response |> Enum.member?("r")
      assert 1 = response |> Enum.count()
      assert [%{"r" => 300}] = response |> Enum.take(1)
      assert %{"r" => 300} = response |> Response.first()
    end

    @tag :core
    test "get all cities", c do
      query = "CREATE (country:Country {name:'C1', id: randomUUID()})"
      Bolty.query(c.conn, query)

      Enum.each(0..333, fn x ->
        query = """
          MATCH(country:Country{name: 'C1'})
          CREATE (city:City {name:'City_#{x}', id: randomUUID()})
          CREATE (country)-[:has_city{id: randomUUID()}]->(city)
        """

        Bolty.query(c.conn, query)
      end)

      all_cities_query = "MATCH (n:City) RETURN n"
      {:ok, %Response{}} = Bolty.query(c.conn, all_cities_query, %{})
    end

    @tag :core
    test "a simple query to get persons", c do
      self = self()

      query = """
        MATCH (n:Person {bolty: true})
        RETURN n.name AS Name
        ORDER BY Name DESC
        LIMIT 5
      """

      {:ok, %Response{} = response} = Bolty.query(c.conn, query, %{}, log: &send(self, &1))
      assert_received %DBConnection.LogEntry{} = entry
      assert %Bolty.Query{} = entry.query

      assert Response.first(response)["Name"] == "Patrick Rothfuss",
             "missing Person database, or data incomplete"
    end

    @tag :core
    test "a simple queries to get persons with many queries", c do
      self = self()

      query = """
        MATCH (n:Person {name:'Patrick Rothfuss'})
        RETURN n.name AS Name
        ORDER BY Name DESC
        LIMIT 1;
        MATCH (n:Person {name:'Kote'})
        RETURN n.name AS Name
        ORDER BY Name DESC
        LIMIT 1;
      """

      {:ok, responses} = Bolty.query_many(c.conn, query, %{}, log: &send(self, &1))
      assert is_list(responses)
      assert Enum.any?(responses, &(is_map(&1) and &1.__struct__ == Response))

      assert Response.first(hd(responses))["Name"] == "Patrick Rothfuss",
             "missing 'The Name Patrick' database, or data incomplete"

      assert Response.first(Enum.at(responses, 1))["Name"] == "Kote",
             "missing 'The Name Kote' database, or data incomplete"
    end

    @tag :bolt_5_x
    test "a query to get a Node with temporal functions", c do
      uuid = "6152f30e-076a-4479-b575-764bf6ab5e38"

      cypher_create = """
        CREATE (user:User{
          uuid: $uuid,
          name: 'John',
          date_time_offset: DATETIME('2024-01-20T18:47:05.850000-06:00'),
          date_time: DATETIME('2000-01-01'),
          date_time2: DATETIME('2000-01-01T00:00:00Z'),
          date_time_with_zona_id: DATETIME('2024-01-21T14:03:45.702000-08:00[America/Los_Angeles]'),
          date: DATE("2024-01-21"),
          localtime: LOCALTIME("15:41:10.222000000"),
          localdatetime: LOCALDATETIME("2024-01-21T15:41:40.706000000"),
          time: TIME("15:41:10.222000000Z"),
          time_with_offset: TIME("15:41:10.222000000-06:00"),
          duration: DURATION("P1Y3M53DT2M5.000054150S")
        })
      """

      Bolty.query!(c.conn, cypher_create, %{uuid: uuid})

      response =
        Bolty.query!(c.conn, "MATCH (user:User {uuid: $uuid }) RETURN user", %{uuid: uuid})

      assert %Bolty.Response{
               results: [
                 %{
                   "user" => %Bolty.Types.Node{
                     id: _,
                     properties: %{
                       "date_time_offset" => date_time_offset,
                       "date_time" => date_time,
                       "date_time2" => date_time2,
                       "date_time_with_zona_id" => date_time_with_zona_id,
                       "date" => date,
                       "localtime" => localtime,
                       "time" => time,
                       "localdatetime" => localdatetime,
                       "time_with_offset" => time_with_offset,
                       "name" => "John",
                       "uuid" => "6152f30e-076a-4479-b575-764bf6ab5e38",
                       "duration" => duration
                     }
                   }
                 }
               ]
             } = response

      assert {:ok, "2024-01-20T18:47:05.850000-06:00"} ==
               DateTimeWithTZOffset.format_param(date_time_offset)

      assert {:ok, "2000-01-01T00:00:00.000000+00:00"} ==
               DateTimeWithTZOffset.format_param(date_time)

      assert {:ok, "2000-01-01T00:00:00.000000+00:00"} ==
               DateTimeWithTZOffset.format_param(date_time2)

      assert "2024-01-21 14:03:45.702000-08:00 PST America/Los_Angeles" ==
               DateTime.to_string(date_time_with_zona_id)

      assert ~D[2024-01-21] == date
      assert ~T[15:41:10.222000] == localtime
      assert ~N[2024-01-21 15:41:40.706000] == localdatetime
      assert {:ok, "15:41:10.222000+00:00"} == TimeWithTZOffset.format_param(time)
      assert {:ok, "15:41:10.222000-06:00"} == TimeWithTZOffset.format_param(time_with_offset)
      # note loss of nanoseconds
      assert {:ok, "P1Y3M53DT2M5.000054S"} == TypesHelper.format_duration(duration)
    end

    @tag :core
    test "A procedure call failure should send reset and not lock the db" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn} = Bolty.start_link(opts)

      cypher_fail = "INVALID CYPHER"
      {:error, %Bolty.Error{code: :syntax_error}} = Bolty.query(conn, cypher_fail)

      cypher_query = """
        MATCH (n:Person {bolty: true})
        RETURN n.name AS Name
        ORDER BY Name DESC
        LIMIT 5
      """

      assert {:ok, %Response{} = response} = Bolty.query(conn, cypher_query, %{})

      assert Response.first(response)["Name"] == "Patrick Rothfuss",
             "missing Person database, or data incomplete"
    end

    @tag :core
    test "executing a Cypher query, with parameters", c do
      cypher = """
        MATCH (n:Person {bolty: true})
        WHERE n.name = $name
        RETURN n.name AS name
      """

      parameters = %{name: "Kote"}

      {:ok, %Response{} = response} = Bolty.query(c.conn, cypher, parameters)
      assert Response.first(response)["name"] == "Kote"
    end

    @tag :core
    test "executing a Cypher query, with duration parameter", c do
      cypher = """
        CREATE(n:User {name: $name, max_session: $max_session}) RETURN n
      """

      parameters = %{name: "Kote", max_session: Duration.new!(day: 1)}

      n =
        Bolty.query!(c.conn, cypher, parameters)
        |> Response.first()
        |> Map.get("n")

      assert n.labels == ["User"]
      assert n.properties["name"] == "Kote"
      assert to_timeout(n.properties["max_session"]) == to_timeout(Duration.new!(day: 1))
    end

    @tag :core
    test "executing a Cypher query, with date_time parameter", c do
      cypher = """
        CREATE(n:User {name: $name, joined: $joined}) RETURN n
      """

      parameters = %{name: "Kote", joined: DateTime.utc_now()}

      n =
        Bolty.query!(c.conn, cypher, parameters)
        |> Response.first()
        |> Map.get("n")

      assert n.labels == ["User"]
      assert n.properties["name"] == "Kote"
      assert n.properties["joined"] == parameters.joined
    end

    @tag :core
    test "executing a Cypher query, with non-UTC zoned DateTime parameter (Europe/Berlin)", c do
      # Regression for issue #10 — UTC round-trip passes even when body semantics
      # are wrong because UTC offset is 0. A zoned DateTime in Europe/Berlin
      # forces the evolved packer to emit UTC-instant seconds (local − offset);
      # if we accidentally emit local-wall-clock seconds on Bolt 5, the server
      # stores an instant shifted by one zone offset and `DateTime.compare/2`
      # returns `:gt` or `:lt` instead of `:eq`.
      cypher = """
        CREATE(n:User {name: $name, joined: $joined}) RETURN n
      """

      {:ok, berlin_now} = DateTime.now("Europe/Berlin")
      parameters = %{name: "Kvothe", joined: berlin_now}

      n =
        Bolty.query!(c.conn, cypher, parameters)
        |> Response.first()
        |> Map.get("n")

      assert n.labels == ["User"]
      assert n.properties["name"] == "Kvothe"
      # Strict equality: server should preserve the zone id string, and under
      # the evolved policy the UTC instant should round-trip exactly. If the
      # evolved packer accidentally emits local-wall-clock seconds instead of
      # UTC seconds, the returned DateTime will be shifted by one zone offset
      # and this assertion fails with a one-hour (or one-CEST-offset) delta.
      assert n.properties["joined"] == parameters.joined
      # Belt-and-braces check: even if the returned zone is canonicalised,
      # the UTC instant must still match. This isolates body-semantics
      # regressions from zone-string canonicalisation drift.
      assert DateTime.compare(n.properties["joined"], parameters.joined) == :eq
    end

    @tag :core
    test "executing a Cypher query, with struct parameters", c do
      cypher = """
        CREATE(n:User $props)
      """

      assert {:ok, %Response{stats: stats, type: type}} =
               Bolty.query(c.conn, cypher, %{
                 props: %BoltyTest.TestUser{
                   name: "Strut",
                   bolty: true,
                   half_life: Duration.new!(year: 1)
                 }
               })

      assert stats["labels-added"] == 1
      assert stats["nodes-created"] == 1
      assert stats["properties-set"] == 3
      assert type == "w"
    end

    @tag :core
    test "executing a Cypher query, with map parameters", c do
      cypher = """
        CREATE(n:User $props)
      """

      assert {:ok, %Response{stats: stats, type: type}} =
               Bolty.query(c.conn, cypher, %{
                 props: %{name: "Mep", bolty: true, half_life: Duration.new!(year: 1)}
               })

      assert stats["labels-added"] == 1
      assert stats["nodes-created"] == 1
      assert stats["properties-set"] == 3
      assert type == "w"
    end

    @tag :core
    test "it returns only known role names", c do
      cypher = """
        MATCH (p)-[r:ACTED_IN]->() where p.bolty RETURN r.roles as roles
        LIMIT 25
      """

      %Response{results: rows} = Bolty.query!(c.conn, cypher)
      roles = ["killer", "sword fighter", "magician", "musician", "many talents"]
      my_roles = Enum.map(rows, & &1["roles"]) |> List.flatten()
      assert my_roles -- roles == [], "found more roles in the db than expected"
    end

    @tag :core
    test "if Patrick Rothfuss wrote The Name of the Wind", c do
      cypher = """
        MATCH (p:Person)-[r:WROTE]->(b:Book {title: 'The Name of the Wind'})
        RETURN p
      """

      %Response{} = rows = Bolty.query!(c.conn, cypher)
      assert Response.first(rows)["p"].properties["name"] == "Patrick Rothfuss"
    end

    @tag :core
    test "executing a raw Cypher query with alias, and no parameters", c do
      cypher = """
        MATCH (p:Person {bolty: true})
        RETURN p, p.name AS name, toUpper(p.name) as NAME,
               coalesce(p.nickname,"n/a") AS nickname,
               { name: p.name, label:head(labels(p))} AS person
        ORDER BY name DESC
      """

      {:ok, %Response{} = r} = Bolty.query(c.conn, cypher)

      assert Enum.count(r) == 3,
             "you're missing some characters from the 'The Name of the Wind' db"

      if row = Response.first(r) do
        assert row["p"].properties["name"] == "Patrick Rothfuss"
        assert is_map(row["p"]), "was expecting a map `p`"
        assert row["person"]["label"] == "Person"
        assert row["NAME"] == "PATRICK ROTHFUSS"
        assert row["nickname"] == "n/a"
        assert row["p"].properties["bolty"] == true
      else
        IO.puts("Did you initialize the 'The Name of the Wind' database?")
      end
    end

    @tag :core
    test "path from: MERGE p=({name:'Alice'})-[:KNOWS]-> ...", c do
      cypher = """
      MERGE p = ({name:'Alice', bolty: true})-[:KNOWS]->({name:'Bob', bolty: true})
      RETURN p
      """

      path =
        Bolty.query!(c.conn, cypher)
        |> Response.first()
        |> Map.get("p")

      assert {2, 1} == {length(path.nodes), length(path.relationships)}
    end

    @tag :core
    test "return a single number from a statement with params", c do
      row = Bolty.query!(c.conn, "RETURN $n AS num", %{n: 10}) |> Response.first()
      assert row["num"] == 10
    end

    @tag :core
    test "run simple statement with complex params", c do
      row =
        Bolty.query!(c.conn, "RETURN $x AS n", %{x: %{abc: ["d", "e", "f"]}})
        |> Response.first()

      assert row["n"]["abc"] == ["d", "e", "f"]
    end

    @tag :core
    test "return an array of numbers", c do
      row = Bolty.query!(c.conn, "RETURN [10,11,21] AS arr") |> Response.first()
      assert row["arr"] == [10, 11, 21]
    end

    @tag :core
    test "return a string", c do
      row = Bolty.query!(c.conn, "RETURN 'Hello' AS salute") |> Response.first()
      assert row["salute"] == "Hello"
    end

    @tag :core
    test "UNWIND range(1, 10) AS n RETURN n", c do
      assert %Response{results: rows} = Bolty.query!(c.conn, "UNWIND range(1, 10) AS n RETURN n")
      assert {1, 10} == rows |> Enum.map(& &1["n"]) |> Enum.min_max()
    end

    @tag :core
    test "MERGE (k:Person {name:'Kote'}) RETURN k", c do
      k =
        Bolty.query!(c.conn, "MERGE (k:Person {name:'Kote', bolty: true}) RETURN k LIMIT 1")
        |> Response.first()
        |> Map.get("k")

      assert k.labels == ["Person"]
      assert k.properties["name"] == "Kote"
    end

    @tag :core
    test "query/2 and query!/2", c do
      assert r = Bolty.query!(c.conn, "RETURN [10,11,21] AS arr")
      assert [10, 11, 21] = Response.first(r)["arr"]

      assert {:ok, %Response{} = r} = Bolty.query(c.conn, "RETURN [10,11,21] AS arr")
      assert [10, 11, 21] = Response.first(r)["arr"]
    end

    @tag :core
    test "create a Bob node and check it was deleted afterwards", c do
      assert %Response{stats: stats} =
               Bolty.query!(c.conn, "CREATE (a:Person {name:'Bob'})")

      assert stats["labels-added"] == 1
      assert stats["nodes-created"] == 1
      assert stats["properties-set"] == 1

      assert ["Bob"] ==
               Bolty.query!(c.conn, "MATCH (a:Person {name: 'Bob'}) RETURN a.name AS name")
               |> Enum.map(& &1["name"])

      assert %Response{stats: stats} =
               Bolty.query!(c.conn, "MATCH (a:Person {name:'Bob'}) DELETE a")

      assert stats["nodes-deleted"] == 1
    end

    @tag :core
    test "can execute a query after a failure", c do
      assert {:error, _} = Bolty.query(c.conn, "INVALID CYPHER")
      assert {:ok, %Response{results: [%{"n" => 22}]}} = Bolty.query(c.conn, "RETURN 22 as n")
    end

    @tag :core
    test "negative numbers are returned as negative numbers", c do
      assert {:ok, %Response{results: [%{"n" => -1}]}} = Bolty.query(c.conn, "RETURN -1 as n")
    end

    @tag :core
    test "return a simple node", c do
      assert %Response{
               results: [
                 %{
                   "p" => %Bolty.Types.Node{
                     id: _,
                     labels: ["Person"],
                     properties: %{"bolty" => true, "name" => "Patrick Rothfuss"}
                   }
                 }
               ]
             } = Bolty.query!(c.conn, "MATCH (p:Person {name: 'Patrick Rothfuss'}) RETURN p")
    end

    @tag :core
    test "Simple relationship", c do
      cypher = """
        MATCH (p:Person)-[r:WROTE]->(b:Book {title: 'The Name of the Wind'})
        RETURN r
      """

      assert %Response{
               results: [
                 %{
                   "r" => %Bolty.Types.Relationship{
                     end: _,
                     id: _,
                     properties: %{},
                     start: _,
                     type: "WROTE"
                   }
                 }
               ]
             } = Bolty.query!(c.conn, cypher)
    end

    @tag :core
    test "simple path", c do
      cypher = """
      MERGE p = ({name:'Alice', bolty: true})-[:KNOWS]->({name:'Bob', bolty: true})
      RETURN p
      """

      assert %Response{
               results: [
                 %{
                   "p" => %Bolty.Types.Path{
                     nodes: [
                       %Bolty.Types.Node{
                         id: _,
                         labels: [],
                         properties: %{"bolty" => true, "name" => "Alice"}
                       },
                       %Bolty.Types.Node{
                         id: _,
                         labels: [],
                         properties: %{"bolty" => true, "name" => "Bob"}
                       }
                     ],
                     relationships: [
                       %Bolty.Types.UnboundRelationship{
                         id: _,
                         properties: %{},
                         type: "KNOWS"
                       }
                     ],
                     sequence: [1, 1]
                   }
                 }
               ]
             } = Bolty.query!(c.conn, cypher)
    end

    @tag :bolt_5_x
    test "Cypher with plan result", c do
      assert %Response{plan: plan} = Bolty.query!(c.conn, "EXPLAIN RETURN 1")
      refute plan == nil
      assert Regex.match?(~r/[3|4|5]/iu, plan["args"]["planner-version"])
    end

    @tag :bolt_5_x
    test "EXPLAIN MATCH (n), (m) RETURN n, m", c do
      assert %Response{notifications: notifications, plan: plan} =
               Bolty.query!(c.conn, "EXPLAIN MATCH (n), (m) RETURN n, m")

      refute notifications == nil
      refute plan == nil

      if Regex.match?(~r/CYPHER 3/iu, plan["args"]["planner-version"]) do
        assert "CartesianProduct" ==
                 plan["children"]
                 |> List.first()
                 |> Map.get("operatorType")
      else
        assert(
          "CartesianProduct@neo4j" ==
            plan["children"]
            |> List.first()
            |> Map.get("operatorType")
        )
      end
    end

    @tag :bolt_5_x
    test "Cypher point() constructor accepts a Map parameter", c do
      # Cypher's `point()` function requires a Map argument — it does not
      # accept a native Bolt Point. Users who want to construct a Point via
      # Cypher pass a plain Map; users who want to store/return a Point as
      # data pass a `%Bolty.Types.Point{}` directly (see the property-store
      # tests above).
      query = "RETURN point($point_data) AS pt"
      params = %{point_data: %{x: 50, y: 60.5}}

      assert {:ok, %Response{results: res}} = Bolty.query(c.conn, query, params)

      assert res == [
               %{
                 "pt" => %Bolty.Types.Point{
                   crs: "cartesian",
                   height: nil,
                   latitude: nil,
                   longitude: nil,
                   srid: 7203,
                   x: 50.0,
                   y: 60.5,
                   z: nil
                 }
               }
             ]
    end

    # Reproducers for #32: a `%Bolty.Types.Point{}` parameter must reach the
    # server as a native PackStream Point, not as a Map. Until the fix lands,
    # these all fail with a Neo4j TypeError because Neo4j refuses Maps as
    # property values.
    @tag :bolt_5_x
    test "store Point as node property — wgs-84 2D", c do
      point = Point.create(:wgs_84, 151.2093, -33.8688)
      query = "CREATE (n:PointTest {p: $p}) RETURN n.p AS p"

      assert {:ok, %Response{results: [%{"p" => ^point}]}} =
               Bolty.query(c.conn, query, %{p: point})
    end

    @tag :bolt_5_x
    test "store Point as node property — wgs-84 3D", c do
      point = Point.create(:wgs_84, 151.2093, -33.8688, 42.0)
      query = "CREATE (n:PointTest {p: $p}) RETURN n.p AS p"

      assert {:ok, %Response{results: [%{"p" => ^point}]}} =
               Bolty.query(c.conn, query, %{p: point})
    end

    @tag :bolt_5_x
    test "store Point as node property — cartesian 2D", c do
      point = Point.create(:cartesian, 10.0, 20.0)
      query = "CREATE (n:PointTest {p: $p}) RETURN n.p AS p"

      assert {:ok, %Response{results: [%{"p" => ^point}]}} =
               Bolty.query(c.conn, query, %{p: point})
    end

    @tag :bolt_5_x
    test "store Point as node property — cartesian 3D", c do
      point = Point.create(:cartesian, 10.0, 20.0, 30.0)
      query = "CREATE (n:PointTest {p: $p}) RETURN n.p AS p"

      assert {:ok, %Response{results: [%{"p" => ^point}]}} =
               Bolty.query(c.conn, query, %{p: point})
    end

    @tag :bolt_5_x
    test "store array of Points as node property", c do
      points = [
        Point.create(:wgs_84, 151.2093, -33.8688),
        Point.create(:wgs_84, 144.9631, -37.8136),
        Point.create(:wgs_84, 153.0260, -27.4705)
      ]

      query = "CREATE (n:PointTest {ps: $ps}) RETURN n.ps AS ps"

      assert {:ok, %Response{results: [%{"ps" => ^points}]}} =
               Bolty.query(c.conn, query, %{ps: points})
    end

    @tag :bolt_5_x
    test "store Point with integer coordinate inputs as node property", c do
      # Point.create/3 normalises integers to floats; the round-tripped value
      # therefore comes back with float coordinates.
      point = Point.create(:cartesian, 10, 20)
      query = "CREATE (n:PointTest {p: $p}) RETURN n.p AS p"

      assert {:ok, %Response{results: [%{"p" => ^point}]}} =
               Bolty.query(c.conn, query, %{p: point})

      assert %Point{x: 10.0, y: 20.0} = point
    end

    @tag :bolt_5_x
    test "nil parameter where a Point would otherwise sit", c do
      # `nil` should pass through untouched — Neo4j treats a null property
      # value as "do not set the property", so the node has no `p` key.
      query = "CREATE (n:PointTest {p: $p}) RETURN n.p AS p, properties(n) AS props"

      assert {:ok, %Response{results: [%{"p" => nil, "props" => %{}}]}} =
               Bolty.query(c.conn, query, %{p: nil})
    end

    @tag :core
    @tag :bolt_5_x
    test "Duration as Cypher input: datetime + duration → datetime", c do
      # Exercises DURATION-as-input. Cypher's `+` operator between a datetime
      # and a duration requires a proper DURATION on the right — if the packer
      # regresses to ISO-8601 string serialisation (the pre-#8 bug), the server
      # responds with a type error rather than performing the arithmetic.
      #
      # Also exercises the policy-driven DateTime packer we fixed for #10:
      # $t is a `%DateTime{}` and must round-trip correctly on every negotiated
      # Bolt version.
      query = "RETURN $t + $d AS result"

      params = %{
        t: ~U[2020-01-01 00:00:00Z],
        d: %Duration{year: 1, minute: 30}
      }

      assert {:ok, %Response{results: [%{"result" => result}]}} =
               Bolty.query(c.conn, query, params)

      # Neo4j applies month arithmetic first, then seconds — so 2020-01-01 +
      # 1 year + 30 min = 2021-01-01 00:30:00 UTC. Compare by instant: the
      # server may return microsecond precision {0, 6} where the sigil gives
      # {0, 0}, and that's a representation detail we don't want to assert on.
      assert DateTime.compare(result, ~U[2021-01-01 00:30:00Z]) == :eq
    end

    @tag :core
    @tag :bolt_5_x
    test "Duration as Cypher output: duration.inSeconds(t1, t2) → duration", c do
      # Exercises DURATION-as-output. The server computes the duration from
      # two datetimes; bolty decodes it via `TypesHelper.create_duration/4`,
      # which splits the raw (months, days, seconds, nanoseconds) tuple into
      # year/month/day/hour/minute/second/microsecond buckets.
      #
      # `duration.inSeconds/2` is preferred over `duration.between/2` because
      # it returns a deterministic seconds-only duration — `between` returns a
      # compound (months+days+seconds) duration whose canonical form depends on
      # server calendar logic and is harder to pin down in an assertion.
      query = "RETURN duration.inSeconds($t1, $t2) AS d"

      params = %{
        t1: ~U[2020-01-01 00:00:00Z],
        t2: ~U[2020-01-01 01:30:00Z]
      }

      # 5400 seconds → create_duration splits into 1h 30m 0s. year/month/week/
      # day are all 0; microsecond tuple is {0, 6} because create_duration
      # hardcodes 6-digit precision.
      expected = %Duration{
        year: 0,
        month: 0,
        week: 0,
        day: 0,
        hour: 1,
        minute: 30,
        second: 0,
        microsecond: {0, 6}
      }

      assert {:ok, %Response{results: [%{"d" => ^expected}]}} =
               Bolty.query(c.conn, query, params)
    end
  end

  defp connect(c) do
    {:ok, conn} = Bolty.start_link(@opts)
    Map.put(c, :conn, conn)
  end

  defp truncate(c) do
    Bolty.query!(c.conn, "MATCH (n) DETACH DELETE n")
    c
  end

  defp rebuild_fixtures(c) do
    Bolty.Test.Fixture.create_graph(c.conn, :bolty)
    c
  end
end
