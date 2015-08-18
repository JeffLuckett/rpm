# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require 'new_relic/agent/datastores/mongo'
require 'helpers/mongo_metric_builder'

if NewRelic::Agent::Datastores::Mongo.is_supported_version? &&
    NewRelic::Agent::Datastores::Mongo.is_monitoring_enabled?
  module NewRelic
    module Agent
      module Instrumentation
        class Mongo2InstrumentationTest < Minitest::Test
          include Mongo
          include TestHelpers::MongoMetricBuilder

          def setup
            @client = Mongo::Client.new(["#{$mongo.host}:#{$mongo.port}"])
            @database_name = "multiverse"
            @client.use(@database_name)
            @database = @client.database

            @collection_name = "tribbles-#{SecureRandom.hex(16)}"
            @collection = @database.collection(@collection_name)

            @tribbles = [{'name' => 'soterios johnson'}, {'name' => 'wes mantooth'}]

            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
            NewRelic::Agent.drop_buffered_data
          end

          def teardown
            NewRelic::Agent.drop_buffered_data
            @collection.drop
          end

          def test_records_metrics_for_insert_one
            @collection.insert_one(@tribbles.first)

            metrics = build_test_metrics(:insertOne)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_insert_many
            @collection.insert_many(@tribbles)

            metrics = build_test_metrics(:insertMany)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_delete_one
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.delete_one(@tribbles.first)

            metrics = build_test_metrics(:deleteOne)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_delete_many
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.delete_many(@tribbles.first)

            metrics = build_test_metrics(:deleteMany)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_replace_one
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.replace_one(@tribbles[0], @tribbles[1])

            metrics = build_test_metrics(:replaceOne)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_update_one
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.update_one(@tribbles[0], "$set" => @tribbles[1])

            metrics = build_test_metrics(:updateOne)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_update_many
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.update_many(@tribbles[0], "$set" => @tribbles[1])

            metrics = build_test_metrics(:updateMany)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.find(@tribbles.first).to_a

            metrics = build_test_metrics(:find)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find_one_and_delete
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.find_one_and_delete(@tribbles.first)

            metrics = build_test_metrics(:findOneAndDelete)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find_one_and_replace
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.find_one_and_replace(@tribbles[0], @tribbles[1])

            metrics = build_test_metrics(:findOneAndReplace)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find_one_and_update
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            @collection.find_one_and_update(@tribbles[0], "$set" => @tribbles[1])

            metrics = build_test_metrics(:findOneAndUpdate)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_distinct
            @collection.distinct('name')

            metrics = build_test_metrics(:distinct)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_count
            @collection.count

            metrics = build_test_metrics(:count)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_drop_collection
            @collection.drop

            metrics = build_test_metrics(:drop)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_web_scoped_metrics
            in_web_transaction("webby") do
              @collection.insert_one(@tribbles.first)
            end

            metric = statement_metric(:insert)
            assert_metrics_recorded([[metric, "webby"]])
          end

          def statement_metric(action)
            metrics = build_test_metrics(action)
            metrics.select { |m| m.start_with?("Datastore/statement") }.first
          end

          def test_background_scoped_metrics
            in_background_transaction("backed-up") do
              @collection.insert_one(@tribbles.first)
            end

            metric = statement_metric(:insert)
            assert_metrics_recorded([[metric, "backed-up"]])
          end

          def test_notices_nosql
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)

              node = find_last_transaction_node
            end

            expected = {
              :database   => @database_name,
              :collection => @collection_name,
              :operation  => :insert
            }

            result = node.params[:statement]

            assert_equal expected, result
          end

          def test_noticed_nosql_includes_operation
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)
              node = find_last_transaction_node
            end

            query = node.params[:statement]

            assert_equal :insert, query[:operation]
          end

          def test_noticed_nosql_includes_update_one_operation
            node = nil

            in_transaction do
              @collection.update_one(@tribbles[0], @tribbles[1])

              node = find_last_transaction_node
            end

            query = node.params[:statement]

            assert_equal :update, query[:operation]
          end

          def test_noticed_nosql_includes_find_operation
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)
              @collection.find(@tribbles.first).to_a
              node = find_last_transaction_node
            end

            query = node.params[:statement]

            assert_equal :find, query[:operation]
          end

          def test_noticed_nosql_does_not_contain_documents
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)
              node = find_last_transaction_node
            end

            statement = node.params[:statement]

            refute statement.keys.include?(:documents), "Noticed NoSQL should not include documents: #{statement}"
          end

          def test_noticed_nosql_does_not_contain_selector_values
            @collection.insert_one({'password' => '$ecret'})
            node = nil

            in_transaction do
              @collection.delete_one({'password' => '$ecret'})
              node = find_last_transaction_node
            end

            statement = node.params[:statement]

            refute statement.inspect.include?('$secret')

            assert_equal '?', statement[:selector]['password']
          end

          def test_web_requests_record_all_web_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
            @collection.insert_one(@tribbles.first)

            metrics = build_test_metrics(:insert)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_web_requests_do_not_record_all_other_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
            @collection.insert_one(@tribbles.first)

            assert_metrics_not_recorded(['Datastore/allOther'])
          end

          def test_other_requests_record_all_other_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
            @collection.insert_one(@tribbles.first)

            metrics = build_test_metrics(:insert)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_other_requests_do_not_record_all_web_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
            @collection.insert_one(@tribbles.first)

            assert_metrics_not_recorded(['Datastore/allWeb'])
          end
        end
      end
    end
  end
end