/*
    Grappling hook by bes#4339

    Thanks to msc and whole amazing wf community
*/
Hook[] Hookers( maxClients );

Cvar hook_enabled( "hook_enabled", "1", 0 );
Cvar hook_limit( "hook_limit", "1", 0 );
//Cvar hook_insta( "hook_insta", "1", 0 );

bool isHookEnabled;

int sndHook = G_SoundIndex( "sounds/world/player_respawn", false );

class Hook 
{
    Client@ client;
    Entity@ player;

    Entity@ beam;
    Entity@ groundEntity;

    Vec3 fwdTarget;

    bool isActive;
    bool isActivePosition;

    Vec3 hookEndPos;

    float hookLength;

    Hook()
    {
        this.isActive = false;
        this.isActivePosition = false;
    }
    ~Hook(){}
    
    void HookBeamInit()
    {
        @this.beam = @G_SpawnEntity( "hook_beam" );
        this.beam.modelindex = 1;
            
        this.beam.frame = 8;
        this.beam.type = ET_BEAM;
        this.beam.svflags = SVF_BROADCAST | SVF_TRANSMITORIGIN2;// | SVF_PROJECTILE; // SVF_BROADCAST SVF_NOCLIENT
        this.beam.svflags &= ~SVF_NOCLIENT;
        this.beam.moveType = MOVETYPE_TOSS; //MOVETYPE_LINEARPROJECTILE; 
        this.beam.solid = SOLID_TRIGGER;

        this.beam.linkEntity();
    }

    //void HookThink();
    //void HookFire();
    //void HookReset();

    void Update() 
    {
        // if (make hook votable) 
        // init hook beam here
        if ( @this.beam == null )
        {
            HookBeamInit();
        }

        if ( this.isActive == true ) 
        {
            if ( client.getEnt().isGhosting() )
            {
                this.isActive = false;
                return;
            }
            if ( !(hook_enabled.boolean) )
            {
                this.isActive = false;
                G_PrintMsg( client.getEnt(), "Hook disabled via callvote\n" );
                return;
            }

            Vec3 playerFireOrigin;

            // Calculate first position and draw (beam)hook
            if ( this.isActivePosition == false )
            {
                // Disable crounching
                client.pmoveFeatures = client.pmoveFeatures & ~( PMFEAT_CROUCH );
                
                // First beam origin set to 20 up
                playerFireOrigin = client.getEnt().origin + Vec3( 0, 0, 20 );

                Vec3 player_look;
                player_look = playerFireOrigin + this.fwdTarget * 10000; // hook lenght limit
                
                // !!!!! DO SOMETHING IF -1
                Trace tr; // tr.ent: -1 = nothing; 0 = wall; 1 = player
                tr.doTrace( playerFireOrigin, Vec3(), Vec3(), player_look, 0, MASK_SOLID ); //MASK_SHOT MASK_SOLID
                
                this.hookEndPos = tr.get_endPos();

                // Sets beam entity to end pos
                this.beam.set_origin2( this.hookEndPos );

                this.isActivePosition = true;

                // Unstuck player
                if (client.getEnt().groundEntity != null) 
                    client.getEnt().origin = client.getEnt().origin + Vec3( 0, 0, 1);

                // Make a "sound" effect
                client.getEnt().respawnEffect();
                //G_PositionedSound( playerFireOrigin, CHAN_AUTO, sndHook, ATTN_DISTANT );
                
                //Vec3 _hookLen = this.hookEndPos - client.getEnt().origin;
                //this.hookLength = _hookLen.length();

                //client.getEnt().moveType = MOVETYPE_FLY;
            }

            //DEFINE HOOK SCALE!!!!!!
            Vec3 dir, v0, dv, v;
            
            // Define knockback scale
            float hookScale = 30;
      
            dir = this.hookEndPos - client.getEnt().origin;
            float dist = dir.length();
            dir.normalize();
            
            //if ( hook_state == HOOK_RELEASE )
            //TODO: pull rope

            //pull player

            v = client.getEnt().get_velocity();

            
            if ( dist < 300)
                v = ( v + dir * hookScale ) * 0.98;
            else
                v = v + dir * hookScale;
            
            if ( hook_limit.boolean )
            {
                // TODO! allow gain speed while hook (rocketjumping etc)
                if ( v.length() > 2200 )
                {
                    
                    //float _tempvel = v.length();
                    v.normalize();
                    v = v * 2200;
                }
            }

            client.getEnt().set_velocity( v );
            
            //Drawcd  hook beam
            this.beam.svflags &= ~SVF_NOCLIENT;
            this.beam.set_origin( client.getEnt().origin );
        }
        else if ( isActive == false )
        {
            this.beam.svflags |= SVF_NOCLIENT;
            this.isActivePosition = false;
            client.pmoveFeatures = client.pmoveFeatures | ( PMFEAT_CROUCH );
            //client.getEnt().moveType = MOVETYPE_PLAYER;
        }
    }
}