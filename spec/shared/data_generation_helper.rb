def create_model(generation_low, generation_high, model_type, default_attrs)
  attrs = { :generation_low => generation_low,
            :generation_high => generation_high }.merge(default_attrs)

  instance = model_type.new(attrs)
  # status should be protected if present, so needs to be assigned separately
  if instance.respond_to?(:status=)
    instance.status = default_attrs[:status]
  end
  instance.save!
  return instance
end

module SharedBehaviours

  module DataGenerationHelper

    shared_examples_for "a model that exists in data generations" do

      describe 'when the data generation is set for all models controlled by data generations' do

        it 'should have the scope for the generation set in the call' do
          FixMyTransport::DataGenerations.in_generation(PREVIOUS_GENERATION) do
            condition_string = ["#{@model_type.quoted_table_name}.generation_low <= ?",
                                "AND #{@model_type.quoted_table_name}.generation_high >= ?"].join(" ")
            expected_scope = {:conditions => [ condition_string, PREVIOUS_GENERATION, PREVIOUS_GENERATION ]}
            @model_type.send(:scope, :find).should == expected_scope
          end
        end

        it 'should have the default scope after the call' do
          condition_string = ["#{@model_type.quoted_table_name}.generation_low <= ?",
                              "AND #{@model_type.quoted_table_name}.generation_high >= ?"].join(" ")
          expected_scope = {:conditions => [ condition_string , CURRENT_GENERATION, CURRENT_GENERATION ]}
          FixMyTransport::DataGenerations.in_generation(PREVIOUS_GENERATION) do
          end
          @model_type.send(:scope, :find).should == expected_scope
        end

      end

      describe 'when the class is set to replayable' do

        before do
          @model_type.replayable = true
        end

        it 'should be replayable' do
          instance = @model_type.new
          instance.replayable.should == true
        end

      end

      describe 'when the class is set to not replayable' do

        before do
          @model_type.replayable = false
        end

        it 'should not be replayable' do
          instance = @model_type.new
          instance.replayable.should == false
        end

      end

      describe 'when the class is not set to either replayable or not replayable' do

        before do
          @model_type.replayable = nil
        end

        it 'should be replayable' do
          instance = @model_type.new
          instance.replayable.should == true
        end

      end

      describe 'when asked for an identity hash' do

        it 'should return an identity hash for an example instance' do
          @model_type.new(@valid_attributes).identity_hash().should == @expected_identity_hash
        end

        it 'should return a temporary identity hash for an example instance or raise an error if no temporary identity keys are defined' do
          if @model_type.data_generation_options_hash[:temporary_identity_fields]
            @model_type.new(@valid_attributes).temporary_identity_hash().should == @expected_temporary_identity_hash
          else
            @expected_error = "No temporary identity fields have been defined for #{@model_type}"
            lambda{ @model_type.new(@valid_attributes).temporary_identity_hash() }.should raise_error(@expected_error)
          end
        end

      end

      describe 'when finding a model in another generation' do

        it 'should find a model in the generation' do
          @old_instance = create_model(generation_low=PREVIOUS_GENERATION, generation_high=PREVIOUS_GENERATION, @model_type, @default_attrs)
          @model_type.in_generation(PREVIOUS_GENERATION){ @model_type.find(@old_instance.id) }.should == @old_instance
          @old_instance.destroy
        end

        it 'should not find a model in the current generation' do
          @current_instance = create_model(generation_low=CURRENT_GENERATION, generation_high=CURRENT_GENERATION, @model_type, @default_attrs)
          expected_error = "Couldn't find #{@model_type} with ID=#{@current_instance.id}"
          lambda{ @model_type.in_generation(PREVIOUS_GENERATION){ @model_type.find(@current_instance.id) } }.should raise_error(expected_error)
          @current_instance.destroy
        end

        after do
          @old_instance.destroy if @old_instance
          @current_instance.destroy if @current_instance
        end
      end

      describe 'when finding a model in any generation' do

        it 'should find a model in a previous generation' do
          @old_instance = create_model(generation_low=PREVIOUS_GENERATION, generation_high=PREVIOUS_GENERATION, @model_type, @default_attrs)
          @model_type.in_any_generation{ @model_type.find(@old_instance.id) }.should == @old_instance
          @old_instance.destroy
        end

        it 'should find a model in the current generation' do
          @current_instance = create_model(generation_low=CURRENT_GENERATION, generation_high=CURRENT_GENERATION, @model_type, @default_attrs)
          @model_type.in_any_generation(){ @model_type.find(@current_instance.id) }.should == @current_instance
          @current_instance.destroy
        end

        after do
          @old_instance.destroy if @old_instance
          @current_instance.destroy if @current_instance
        end

      end

      describe "when finding the successor to a set of find parameters" do

        before do
          @find_params = [55]
          if @scope_model
            @find_params << { :scope => @default_params[:scope], :include => [@scope_field] }
          end
        end

        it 'should look for an instance matching the find parameters in the previous generation' do
          @model_type.should_receive(:in_generation).with(PREVIOUS_GENERATION).and_yield
          # not really testing that this is in the scope of the previous generation
          @model_type.should_receive(:find).with(*@find_params).and_return(@previous)
          @model_type.find_successor(*@find_params)
        end

        describe 'if an instance can be found in a previous generation' do

          before do
            @previous = mock_model(@model_type, :generation_high => PREVIOUS_GENERATION,
                                                :generation_low => PREVIOUS_GENERATION)
            # this stubbed call is called in the scope of the previous generation
            @model_type.stub(:find).with(*@find_params).and_return(@previous)
          end

          it 'should look for the successor to the instance in this generation' do
            @model_type.should_receive(:find).with(:first, :conditions => ['previous_id = ?', @previous.id]).and_return(@successor)
            @model_type.find_successor(*@find_params)
          end

          describe 'if the instance is valid in this generation' do

            before do
              @previous.stub!(:generation_high).and_return(CURRENT_GENERATION)
            end

            it 'should return the instance' do
              @model_type.find_successor(*@find_params).should == @previous
            end

          end

          describe 'if the instance is not valid in this generation' do

            before do
              @previous.stub!(:generation_high).and_return(PREVIOUS_GENERATION)
              @successor = mock_model(@model_type)
              @previous_conditions = { :conditions => ['previous_id = ?', @previous.id] }
            end

            describe 'if there is a successor' do

              before do
                @model_type.stub!(:find).with(:first, @previous_conditions).and_return(@successor)
              end

              it 'should return the successor' do
                @model_type.find_successor(*@find_params).should == @successor
              end

            end

            describe 'if there is no successor' do

              before do
                @model_type.stub!(:find).with(:first, @previous_conditions).and_return(nil)
              end

              it 'should return nil' do
                @model_type.find_successor(*@find_params).should == nil
              end
            end
          end
        end

      end

      describe 'when finding a model' do

        it 'should find a model in the current generation' do
          current_instance = create_model(generation_low=CURRENT_GENERATION, generation_high=CURRENT_GENERATION, @model_type, @default_attrs)
          @model_type.find(current_instance.id).should == current_instance
          current_instance.destroy
        end

        it 'should not find a model in an older generation' do
          current_instance = create_model(generation_low=PREVIOUS_GENERATION, generation_high=PREVIOUS_GENERATION, @model_type, @default_attrs)
          expected_error = "Couldn't find #{@model_type} with ID=#{current_instance.id}"
          lambda{ @model_type.find(current_instance.id) }.should raise_error(expected_error)
          current_instance.destroy
        end

        it 'should find a model that spans the previous generation and the current generation' do
          spanning_instance = create_model(generation_low=PREVIOUS_GENERATION, generation_high=CURRENT_GENERATION, @model_type, @default_attrs)
          @model_type.find(spanning_instance.id).should == spanning_instance
          spanning_instance.destroy
        end

      end

      describe 'when setting generations' do

        it 'should not change existing generation attribute values' do
          instance = @model_type.new
          instance.generation_low = PREVIOUS_GENERATION
          instance.generation_high = PREVIOUS_GENERATION
          instance.should_not_receive(:generation_low=)
          instance.should_not_receive(:generation_high=)
          instance.set_generations
        end

        it 'should set nil generation attributes to the current generation' do
          instance = @model_type.new
          instance.should_receive(:generation_low=).with(CURRENT_GENERATION)
          instance.should_receive(:generation_high=).with(CURRENT_GENERATION)
          instance.set_generations
        end

      end

    end

    shared_examples_for "a model that exists in data generations and has slugs" do

      describe 'when reordering slugs' do

        it 'should order slugs that are identical but in a different sequence from in the previous generation' do
            # create slugs in previous generation
            @first_old_instance = create_model(generation_low=PREVIOUS_GENERATION,
                                              generation_high=PREVIOUS_GENERATION,
                                              @model_type,
                                              @default_attrs)
            @second_old_instance = create_model(generation_low=PREVIOUS_GENERATION,
                                                generation_high=PREVIOUS_GENERATION,
                                                @model_type,
                                                @default_attrs)
            @third_old_instance = create_model(generation_low=PREVIOUS_GENERATION,
                                               generation_high=PREVIOUS_GENERATION,
                                               @model_type,
                                               @default_attrs)
            [@first_old_instance, @second_old_instance, @third_old_instance].each do |instance|
              slug = instance.slug
              Slug.connection.execute("UPDATE slugs set generation_low = #{PREVIOUS_GENERATION}, generation_high = #{PREVIOUS_GENERATION}
                                       WHERE id = #{slug.id}")
            end

            @second_new_instance = create_model(generation_low=CURRENT_GENERATION,
                                                generation_high=CURRENT_GENERATION,
                                                @model_type,
                                                @default_attrs)
            @second_new_instance.previous_id = @second_old_instance.id
            @second_new_instance.save
            @second_new_instance.slug.sequence.should == 1

            @first_new_instance = create_model(generation_low=CURRENT_GENERATION,
                                               generation_high=CURRENT_GENERATION,
                                               @model_type,
                                               @default_attrs)
            @first_new_instance.previous_id = @first_old_instance.id
            @first_new_instance.save
            @first_new_instance.slug.sequence.should == 2

            @third_new_instance = create_model(generation_low=CURRENT_GENERATION,
                                               generation_high=CURRENT_GENERATION,
                                               @model_type,
                                               @default_attrs)
            @third_new_instance.previous_id = @third_old_instance.id
            @third_new_instance.save
            @third_new_instance.slug.sequence.should == 3

            @model_type.normalize_slug_sequences(CURRENT_GENERATION)

            @model_type.find(@second_new_instance.id).slug.sequence.should == 2
            @model_type.find(@first_new_instance.id).slug.sequence.should == 1
            @model_type.find(@third_new_instance.id).slug.sequence.should == 3
        end

        after do
          [@first_old_instance, @second_old_instance, @third_old_instance,
           @first_new_instance, @second_new_instance, @third_new_instance].each do |instance|
            instance.slug.destroy
            instance.slug=nil
            instance.destroy
          end
        end
      end

    end

  end
end